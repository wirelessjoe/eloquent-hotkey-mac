import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

struct DictationConfiguration {
    let microphoneID: String?
    let silenceTimeout: TimeInterval
    let maxDuration: TimeInterval
    let autoStopOnSilence: Bool
}

final class DictationController: NSObject, @unchecked Sendable, AVCaptureAudioDataOutputSampleBufferDelegate {
    private static let minimumReadyBufferedAudio: TimeInterval = 0.18
    private static let stopFlushGracePeriod: TimeInterval = 0.35
    private static let stopNoSpeechTimeout: TimeInterval = 0.9
    private static let logger = Logger(subsystem: "dev.codex.EloquentHotkey", category: "Dictation")

    private let configuration: DictationConfiguration
    private let onReady: (@MainActor @Sendable () -> Void)?
    private let engineQueue = DispatchQueue(label: "dev.codex.EloquentHotkey.dictation")
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var captureSession: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<String, Error>?

    private var startedAt = Date()
    private var lastTranscriptChangeAt = Date()
    private var latestTranscript = ""
    private var transcriptAccumulator = TranscriptAccumulator()
    private var sawSpeech = false
    private var isFinishing = false
    private var stopRequestedAt: Date?
    private var audioCaptureEnded = false
    private var loggedQuietInputBoost = false
    private var didSignalReady = false
    private var bufferedStartupAudio: [AVAudioPCMBuffer] = []
    private var bufferedStartupAudioDuration: TimeInterval = 0
    private var didLogFirstTranscript = false

    init(
        configuration: DictationConfiguration,
        onReady: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onReady = onReady
    }

    func captureAndTranscribe() async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw AppError.recognizerUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.engineQueue.async {
                self.continuation = continuation
                self.configureAndStart(recognizer: recognizer)
            }
        }
    }

    func requestStop() {
        engineQueue.async {
            guard !self.isFinishing else {
                return
            }

            if self.stopRequestedAt == nil {
                self.stopRequestedAt = Date()
                Self.logger.debug("Stop requested by caller")
            }

            self.endAudioCaptureIfNeeded()
            self.finishIfStopRequestExpired()
        }
    }

    private func configureAndStart(recognizer: SFSpeechRecognizer) {
        guard let device = AudioDeviceManager.device(for: configuration.microphoneID) else {
            finish(error: AppError.microphoneUnavailable)
            return
        }

        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(input) else {
                throw AppError.unableToStartRecording("Could not attach the selected microphone.")
            }
            captureSession.addInput(input)

            let output = AVCaptureAudioDataOutput()
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: true,
                AVLinearPCMIsBigEndianKey: false,
            ]
            output.setSampleBufferDelegate(self, queue: engineQueue)

            guard captureSession.canAddOutput(output) else {
                throw AppError.unableToStartRecording("Could not receive audio from the selected microphone.")
            }
            captureSession.addOutput(output)
            captureSession.commitConfiguration()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.contextualStrings = CodingLexicon.contextualPhrases
            request.taskHint = .dictation
            if #available(macOS 13, *) {
                request.addsPunctuation = true
            }
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            self.captureSession = captureSession
            self.output = output
            self.request = request
            self.startedAt = Date()
            self.lastTranscriptChangeAt = Date()
            self.latestTranscript = ""
            self.transcriptAccumulator = TranscriptAccumulator()
            self.sawSpeech = false
            self.isFinishing = false
            self.audioCaptureEnded = false
            self.loggedQuietInputBoost = false
            self.didSignalReady = false
            self.bufferedStartupAudio.removeAll(keepingCapacity: true)
            self.bufferedStartupAudioDuration = 0
            self.didLogFirstTranscript = false

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else {
                    return
                }

                self.engineQueue.async {
                    self.handleRecognition(result: result, error: error)
                }
            }

            Self.logger.debug(
                "Capture session started; autoStopOnSilence=\(self.configuration.autoStopOnSilence, privacy: .public), silenceTimeout=\(self.configuration.silenceTimeout, privacy: .public), maxDuration=\(self.configuration.maxDuration, privacy: .public)"
            )
            startTimer()
            captureSession.startRunning()

            if stopRequestedAt != nil {
                flushBufferedStartupAudioIfNeeded(into: request, signalReady: false, reason: "stop requested before microphone primed")
                endAudioCaptureIfNeeded()
                finishIfStopRequestExpired()
            }
        } catch {
            captureSession.commitConfiguration()
            finish(error: error)
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: engineQueue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.evaluateStopConditions()
        }
        self.timer = timer
        timer.resume()
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let update = transcriptAccumulator.ingest(
                formattedTranscript: result.bestTranscription.formattedString,
                segments: result.bestTranscription.segments.map { segment in
                    TranscriptAccumulator.Segment(
                        timestamp: segment.timestamp,
                        duration: segment.duration,
                        text: segment.substring
                    )
                }
            )
            let transcript = update.transcript

            if transcript != latestTranscript {
                latestTranscript = transcript
                if !transcript.isEmpty {
                    sawSpeech = true
                    lastTranscriptChangeAt = Date()
                    logFirstTranscriptIfNeeded(for: result, transcript: transcript)
                }
            }

            if update.recognizerTranscriptShrank {
                Self.logger.notice("Recognizer returned a less complete transcript snapshot; preserving the more complete accumulated transcript")
            }

            if result.isFinal {
                logFinalTranscript(result, transcript: transcript)
                finishWithCurrentTranscript()
                return
            }
        }

        if let error {
            Self.logger.error("Speech recognition failed: \(error.localizedDescription, privacy: .public)")
            finish(error: error)
            return
        }

        finishIfStopRequestExpired()
    }

    private func evaluateStopConditions() {
        guard !isFinishing else {
            return
        }

        if stopRequestedAt != nil {
            finishIfStopRequestExpired()
            return
        }

        let now = Date()
        if configuration.autoStopOnSilence,
           sawSpeech,
           now.timeIntervalSince(lastTranscriptChangeAt) >= configuration.silenceTimeout {
            Self.logger.debug("Stopping because silence timeout elapsed")
            finishWithCurrentTranscript()
            return
        }

        if !sawSpeech && now.timeIntervalSince(startedAt) >= configuration.maxDuration {
            Self.logger.debug("Stopping because max duration elapsed without speech")
            finish(error: AppError.noSpeechDetected)
            return
        }

        if now.timeIntervalSince(startedAt) >= configuration.maxDuration {
            Self.logger.debug("Stopping because max duration elapsed")
            finishWithCurrentTranscript()
        }
    }

    private func finishIfStopRequestExpired(now: Date = Date()) {
        guard let stopRequestedAt else {
            return
        }

        let transcript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty,
           now.timeIntervalSince(stopRequestedAt) >= Self.stopFlushGracePeriod {
            Self.logger.debug("Returning transcript after stop flush grace period")
            finish(value: transcript)
            return
        }

        if now.timeIntervalSince(stopRequestedAt) >= Self.stopNoSpeechTimeout {
            if transcript.isEmpty {
                Self.logger.debug("Stop request expired without transcript")
                finish(error: AppError.noSpeechDetected)
            } else {
                Self.logger.debug("Returning transcript after stop request timeout")
                finish(value: transcript)
            }
        }
    }

    private func finishWithCurrentTranscript() {
        let transcript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            finish(error: AppError.emptyTranscript)
            return
        }

        finish(value: transcript)
    }

    private func finish(value: String) {
        guard !isFinishing else {
            return
        }

        isFinishing = true
        Self.logger.debug("Dictation finished successfully with \(value.count, privacy: .public) characters")
        tearDown()
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func finish(error: Error) {
        guard !isFinishing else {
            return
        }

        isFinishing = true
        Self.logger.error("Dictation finished with error: \(error.localizedDescription, privacy: .public)")
        tearDown()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func tearDown() {
        timer?.cancel()
        timer = nil

        output?.setSampleBufferDelegate(nil, queue: nil)
        output = nil

        captureSession?.stopRunning()
        captureSession = nil

        request?.endAudio()
        request = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        stopRequestedAt = nil
        audioCaptureEnded = false
        bufferedStartupAudio.removeAll(keepingCapacity: false)
        bufferedStartupAudioDuration = 0
        didSignalReady = false
        didLogFirstTranscript = false
    }

    private func endAudioCaptureIfNeeded() {
        guard !audioCaptureEnded else {
            return
        }

        audioCaptureEnded = true
        output?.setSampleBufferDelegate(nil, queue: nil)
        captureSession?.stopRunning()
        request?.endAudio()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isFinishing, let request else {
            return
        }

        if let boostedBuffer = recognitionBuffer(from: sampleBuffer) {
            appendAudioForRecognition(boostedBuffer, into: request)
        } else {
            if !didSignalReady {
                signalReadyIfNeeded(
                    bufferedAudioDuration: bufferedStartupAudioDuration,
                    reason: "microphone delivered raw audio"
                )
            }
            request.appendAudioSampleBuffer(sampleBuffer)
        }
    }

    private func appendAudioForRecognition(
        _ buffer: AVAudioPCMBuffer,
        into request: SFSpeechAudioBufferRecognitionRequest
    ) {
        guard !didSignalReady else {
            request.append(buffer)
            return
        }

        bufferedStartupAudio.append(buffer)
        bufferedStartupAudioDuration += duration(of: buffer)

        if bufferedStartupAudioDuration >= Self.minimumReadyBufferedAudio {
            flushBufferedStartupAudioIfNeeded(
                into: request,
                signalReady: stopRequestedAt == nil,
                reason: "microphone primed with live audio"
            )
        }
    }

    private func flushBufferedStartupAudioIfNeeded(
        into request: SFSpeechAudioBufferRecognitionRequest,
        signalReady: Bool,
        reason: StaticString
    ) {
        let bufferedAudioDuration = bufferedStartupAudioDuration
        if !bufferedStartupAudio.isEmpty {
            for bufferedBuffer in bufferedStartupAudio {
                request.append(bufferedBuffer)
            }
            bufferedStartupAudio.removeAll(keepingCapacity: true)
            bufferedStartupAudioDuration = 0
        }

        if signalReady {
            signalReadyIfNeeded(
                bufferedAudioDuration: bufferedAudioDuration,
                reason: reason
            )
        }
    }

    private func signalReadyIfNeeded(
        bufferedAudioDuration: TimeInterval,
        reason: StaticString
    ) {
        guard !didSignalReady, stopRequestedAt == nil else {
            return
        }

        didSignalReady = true
        let startupLatency = Date().timeIntervalSince(startedAt)
        Self.logger.notice(
            "Recognizer primed after \(startupLatency, privacy: .public)s with \(bufferedAudioDuration, privacy: .public)s of startup audio buffered; reason=\(reason, privacy: .public)"
        )
        Task { @MainActor [onReady] in
            onReady?()
        }
    }

    private func recognitionBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let audioFormat = AVAudioFormat(streamDescription: streamDescription)
        else {
            return nil
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)
        else {
            return nil
        }

        pcmBuffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else {
            Self.logger.debug("Falling back to raw sample-buffer append because PCM conversion failed with status \(status, privacy: .public)")
            return nil
        }

        if let gain = applyAdaptiveGain(to: pcmBuffer), !loggedQuietInputBoost {
            loggedQuietInputBoost = true
            Self.logger.notice("Boosted quiet microphone input by \(gain, privacy: .public)x for speech recognition")
        }

        return pcmBuffer
    }

    private func applyAdaptiveGain(to buffer: AVAudioPCMBuffer) -> Float? {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = buffer.floatChannelData
        else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return nil
        }

        let stride = Int(buffer.stride)
        var sumSquares: Float = 0
        var peak: Float = 0

        for channelIndex in 0..<channelCount {
            let samples = channelData[channelIndex]
            var sampleIndex = 0

            for _ in 0..<frameLength {
                let sample = samples[sampleIndex]
                let magnitude = abs(sample)
                sumSquares += sample * sample
                peak = max(peak, magnitude)
                sampleIndex += stride
            }
        }

        guard peak > 0 else {
            return nil
        }

        let sampleCount = Float(frameLength * channelCount)
        let rms = sqrt(sumSquares / max(sampleCount, 1))
        let minimumBoostableRMS: Float = 0.018
        guard rms < minimumBoostableRMS else {
            return nil
        }

        let targetRMS: Float = 0.05
        let requestedGain = targetRMS / max(rms, 0.0005)
        let headroomGain = 0.92 / peak
        let gain = min(requestedGain, headroomGain, 4.0)
        guard gain > 1.1 else {
            return nil
        }

        for channelIndex in 0..<channelCount {
            let samples = channelData[channelIndex]
            var sampleIndex = 0

            for _ in 0..<frameLength {
                samples[sampleIndex] *= gain
                sampleIndex += stride
            }
        }

        return gain
    }

    private func logFirstTranscriptIfNeeded(
        for result: SFSpeechRecognitionResult,
        transcript: String
    ) {
        guard !didLogFirstTranscript else {
            return
        }

        didLogFirstTranscript = true
        let elapsedSinceStart = Date().timeIntervalSince(startedAt)
        let firstSegmentTimestamp = result.bestTranscription.segments.first?.timestamp ?? 0
        let lastSegmentEnd = result.bestTranscription.segments.last.map { $0.timestamp + $0.duration } ?? 0

        Self.logger.notice(
            "First transcript arrived after \(elapsedSinceStart, privacy: .public)s; firstSegment=\(firstSegmentTimestamp, privacy: .public)s lastSegmentEnd=\(lastSegmentEnd, privacy: .public)s chars=\(transcript.count, privacy: .public)"
        )

        if firstSegmentTimestamp >= 0.6 {
            Self.logger.notice(
                "Recognizer's first segment started \(firstSegmentTimestamp, privacy: .public)s into captured audio; the opening words were likely missed before transcription stabilized"
            )
        }
    }

    private func logFinalTranscript(
        _ result: SFSpeechRecognitionResult,
        transcript: String
    ) {
        let elapsedSinceStart = Date().timeIntervalSince(startedAt)
        let firstSegmentTimestamp = result.bestTranscription.segments.first?.timestamp ?? 0
        let lastSegmentEnd = result.bestTranscription.segments.last.map { $0.timestamp + $0.duration } ?? 0

        Self.logger.notice(
            "Speech recognizer produced a final result after \(elapsedSinceStart, privacy: .public)s; firstSegment=\(firstSegmentTimestamp, privacy: .public)s lastSegmentEnd=\(lastSegmentEnd, privacy: .public)s chars=\(transcript.count, privacy: .public)"
        )
    }

    private func duration(of buffer: AVAudioPCMBuffer) -> TimeInterval {
        guard buffer.format.sampleRate > 0 else {
            return 0
        }

        return Double(buffer.frameLength) / buffer.format.sampleRate
    }
}
