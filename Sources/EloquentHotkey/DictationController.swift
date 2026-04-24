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
    private var earliestObservedResultStart: TimeInterval?
    private var recordingFileURL: URL?
    private var recordingFile: AVAudioFile?
    private var recordedAudioDuration: TimeInterval = 0

    private struct RecordedAudioFallbackDecision {
        let reason: String
        let audioDuration: TimeInterval
        let finalCoverage: TimeInterval
        let wordsPerSecond: Double
        let charactersPerSecond: Double
    }

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
            self.earliestObservedResultStart = nil
            self.recordingFile = nil
            self.recordingFileURL = nil
            self.recordedAudioDuration = 0

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
            let currentTranscript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentFirstSegmentStart = result.bestTranscription.segments.first?.timestamp ?? 0
            if !result.bestTranscription.segments.isEmpty {
                earliestObservedResultStart = min(
                    earliestObservedResultStart ?? currentFirstSegmentStart,
                    currentFirstSegmentStart
                )
            }

            let update = transcriptAccumulator.ingest(
                formattedTranscript: currentTranscript,
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
                    logTranscriptUpdate(
                        for: result,
                        currentTranscript: currentTranscript,
                        chosenTranscript: transcript,
                        recognizerTranscriptShrank: update.recognizerTranscriptShrank
                    )
                }
            }

            if update.recognizerTranscriptShrank {
                Self.logger.notice("Recognizer returned a less complete transcript snapshot; preserving the more complete accumulated transcript")
            }

            if result.isFinal {
                logFinalTranscript(result, transcript: transcript)
                finishAfterFinalResult(result, liveTranscript: transcript)
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
        Self.logger.notice("Dictation finished successfully with \(value.count, privacy: .public) characters")
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
        stopStreamingRecognition()
        cleanupRecordedAudioArtifacts()
    }

    private func stopStreamingRecognition() {
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

        recordingFile = nil

        stopRequestedAt = nil
        audioCaptureEnded = false
        bufferedStartupAudio.removeAll(keepingCapacity: false)
        bufferedStartupAudioDuration = 0
        didSignalReady = false
        didLogFirstTranscript = false
        earliestObservedResultStart = nil
        recordedAudioDuration = 0
    }

    private func cleanupRecordedAudioArtifacts() {
        recordingFile = nil
        if let recordingFileURL {
            try? FileManager.default.removeItem(at: recordingFileURL)
        }
        recordingFileURL = nil
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

        if let pcmBuffer = pcmBuffer(from: sampleBuffer) {
            if let gain = applyAdaptiveGain(to: pcmBuffer), !loggedQuietInputBoost {
                loggedQuietInputBoost = true
                Self.logger.notice("Boosted quiet microphone input by \(gain, privacy: .public)x for speech recognition")
            }

            appendAudioForRecognition(pcmBuffer, into: request)
            appendRecordedAudio(pcmBuffer)
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

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
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

        return pcmBuffer
    }

    private func appendRecordedAudio(_ buffer: AVAudioPCMBuffer) {
        do {
            if recordingFile == nil {
                let recordingURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("EloquentHotkey-\(UUID().uuidString)")
                    .appendingPathExtension("caf")
                recordingFileURL = recordingURL
                recordingFile = try AVAudioFile(
                    forWriting: recordingURL,
                    settings: buffer.format.settings,
                    commonFormat: buffer.format.commonFormat,
                    interleaved: buffer.format.isInterleaved
                )
            }

            try recordingFile?.write(from: buffer)
            recordedAudioDuration += duration(of: buffer)
        } catch {
            Self.logger.error("Could not record dictation audio for fallback recognition: \(error.localizedDescription, privacy: .public)")
            cleanupRecordedAudioArtifacts()
        }
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

    private func logTranscriptUpdate(
        for result: SFSpeechRecognitionResult,
        currentTranscript: String,
        chosenTranscript: String,
        recognizerTranscriptShrank: Bool
    ) {
        let firstSegmentTimestamp = result.bestTranscription.segments.first?.timestamp ?? 0
        let lastSegmentEnd = result.bestTranscription.segments.last.map { $0.timestamp + $0.duration } ?? 0
        Self.logger.notice(
            "Transcript update currentChars=\(currentTranscript.count, privacy: .public) chosenChars=\(chosenTranscript.count, privacy: .public) firstSegment=\(firstSegmentTimestamp, privacy: .public) lastSegmentEnd=\(lastSegmentEnd, privacy: .public) shrank=\(recognizerTranscriptShrank, privacy: .public)"
        )
    }

    private func finishAfterFinalResult(
        _ result: SFSpeechRecognitionResult,
        liveTranscript: String
    ) {
        let cleanedLiveTranscript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedLiveTranscript.isEmpty else {
            finish(error: AppError.emptyTranscript)
            return
        }

        guard let fallbackDecision = recordedAudioFallbackDecision(for: result, liveTranscript: cleanedLiveTranscript),
              let recordingFileURL
        else {
            finish(value: cleanedLiveTranscript)
            return
        }

        let finalStart = result.bestTranscription.segments.first?.timestamp ?? 0
        let earliestStart = earliestObservedResultStart ?? finalStart
        Self.logger.notice(
            "Live transcript looks incomplete (reason=\(fallbackDecision.reason, privacy: .public), earliestStart=\(earliestStart, privacy: .public)s, finalStart=\(finalStart, privacy: .public)s, finalCoverage=\(fallbackDecision.finalCoverage, privacy: .public)s, audioDuration=\(fallbackDecision.audioDuration, privacy: .public)s, wordsPerSecond=\(fallbackDecision.wordsPerSecond, privacy: .public), charactersPerSecond=\(fallbackDecision.charactersPerSecond, privacy: .public)). Retrying recognition on the recorded audio."
        )

        stopStreamingRecognition()

        Task { [weak self, recordingFileURL] in
            do {
                let fallbackResult = try await Self.transcribeRecordedAudio(at: recordingFileURL)
                let fallbackTranscript = fallbackResult.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackStart = fallbackResult.bestTranscription.segments.first?.timestamp ?? 0
                let liveWords = Self.normalizedWords(in: cleanedLiveTranscript)
                let fallbackWords = Self.normalizedWords(in: fallbackTranscript)
                let liveRetentionInFallback = Self.orderedWordRetention(reference: liveWords, candidate: fallbackWords)
                let chosenTranscript = Self.preferredTranscript(
                    liveTranscript: cleanedLiveTranscript,
                    liveStart: finalStart,
                    fallbackTranscript: fallbackTranscript,
                    fallbackStart: fallbackStart
                )

                Self.logger.notice(
                    "Recorded-audio fallback result liveChars=\(cleanedLiveTranscript.count, privacy: .public), fallbackChars=\(fallbackTranscript.count, privacy: .public), liveWords=\(liveWords.count, privacy: .public), fallbackWords=\(fallbackWords.count, privacy: .public), retention=\(liveRetentionInFallback, privacy: .public), fallbackStart=\(fallbackStart, privacy: .public)s"
                )

                if chosenTranscript != cleanedLiveTranscript {
                    Self.logger.notice(
                        "Recorded-audio fallback recovered a fuller transcript (liveChars=\(cleanedLiveTranscript.count, privacy: .public), fallbackChars=\(fallbackTranscript.count, privacy: .public))"
                    )
                } else {
                    Self.logger.notice("Recorded-audio fallback did not improve the live transcript")
                }

                self?.engineQueue.async { [weak self] in
                    self?.finish(value: chosenTranscript)
                }
            } catch {
                Self.logger.error("Recorded-audio fallback failed: \(error.localizedDescription, privacy: .public)")
                self?.engineQueue.async { [weak self] in
                    self?.finish(value: cleanedLiveTranscript)
                }
            }
        }
    }

    private func recordedAudioFallbackDecision(
        for result: SFSpeechRecognitionResult,
        liveTranscript: String
    ) -> RecordedAudioFallbackDecision? {
        let finalStart = result.bestTranscription.segments.first?.timestamp ?? 0
        let finalEnd = result.bestTranscription.segments.last.map { $0.timestamp + $0.duration } ?? finalStart
        let finalCoverage = max(0, finalEnd - finalStart)
        let earliestStart = earliestObservedResultStart ?? finalStart
        let liveWordCount = Self.normalizedWords(in: liveTranscript).count
        let elapsedSinceStart = Date().timeIntervalSince(startedAt)
        let audioDuration = max(recordedAudioDuration, elapsedSinceStart)
        let wordsPerSecond = Double(liveWordCount) / max(audioDuration, 1)
        let charactersPerSecond = Double(liveTranscript.count) / max(audioDuration, 1)

        func decision(_ reason: String) -> RecordedAudioFallbackDecision {
            RecordedAudioFallbackDecision(
                reason: reason,
                audioDuration: audioDuration,
                finalCoverage: finalCoverage,
                wordsPerSecond: wordsPerSecond,
                charactersPerSecond: charactersPerSecond
            )
        }

        if finalStart - earliestStart >= 1.0 {
            return decision("final result shifted later than earlier partials")
        }

        if audioDuration >= 8.0 && liveWordCount <= 3 {
            return decision("long recording produced almost no words")
        }

        if audioDuration >= 10.0 && (wordsPerSecond < 0.9 || charactersPerSecond < 4.5) {
            return decision("long recording produced unusually sparse text")
        }

        if audioDuration >= 8.0 && finalCoverage > 0 && finalCoverage / audioDuration < 0.55 {
            return decision("recognized segment coverage is much shorter than captured audio")
        }

        if audioDuration >= 8.0 && finalCoverage <= 0.25 && liveWordCount >= 6 {
            return decision("recognizer returned unreliable segment coverage for a long recording")
        }

        return nil
    }

    private static func transcribeRecordedAudio(at url: URL) async throws -> SFSpeechRecognitionResult {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable
        else {
            throw AppError.recognizerUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            request.contextualStrings = CodingLexicon.contextualPhrases
            request.taskHint = .dictation
            if #available(macOS 13, *) {
                request.addsPunctuation = true
            }
            // The live on-device recognizer can occasionally return only a sparse
            // partial for longer dictations, so the rescue pass allows Apple's
            // recognizer to choose the best available path for the saved audio.

            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    task?.cancel()
                    continuation.resume(returning: result)
                    return
                }

                if let error {
                    task?.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func preferredTranscript(
        liveTranscript: String,
        liveStart: TimeInterval,
        fallbackTranscript: String,
        fallbackStart: TimeInterval
    ) -> String {
        let cleanedFallback = fallbackTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedFallback.isEmpty else {
            return liveTranscript
        }

        let liveWords = normalizedWords(in: liveTranscript)
        let fallbackWords = normalizedWords(in: cleanedFallback)
        let liveRetentionInFallback = orderedWordRetention(reference: liveWords, candidate: fallbackWords)
        let liveScore = transcriptScore(liveTranscript)
        let fallbackScore = transcriptScore(cleanedFallback)
        let fallbackAddsSubstantialContent = fallbackWords.count >= liveWords.count + 4
            || cleanedFallback.count >= liveTranscript.count + 24

        if fallbackStart + 1.0 < liveStart,
           fallbackScore >= liveScore,
           liveRetentionInFallback >= 0.5 {
            return cleanedFallback
        }

        if liveWords.count <= 3,
           fallbackWords.count >= liveWords.count + 3 {
            return cleanedFallback
        }

        if fallbackAddsSubstantialContent,
           liveRetentionInFallback >= 0.55 {
            return cleanedFallback
        }

        if fallbackScore > liveScore,
           liveRetentionInFallback >= 0.65 {
            return cleanedFallback
        }

        return liveTranscript
    }

    private func duration(of buffer: AVAudioPCMBuffer) -> TimeInterval {
        guard buffer.format.sampleRate > 0 else {
            return 0
        }

        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    private static func transcriptScore(_ transcript: String) -> Int {
        (normalizedWords(in: transcript).count * 1_000) + transcript.count
    }

    private static func normalizedWords(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { character in
            !(character.isLetter || character.isNumber || character == "/" || character == "_" || character == "-")
        }).map(String.init)
    }

    private static func orderedWordRetention(reference: [String], candidate: [String]) -> Double {
        guard !reference.isEmpty else {
            return 1
        }

        var candidateIndex = 0
        var matches = 0

        for word in reference {
            while candidateIndex < candidate.count {
                if candidate[candidateIndex] == word {
                    matches += 1
                    candidateIndex += 1
                    break
                }

                candidateIndex += 1
            }
        }

        return Double(matches) / Double(reference.count)
    }
}
