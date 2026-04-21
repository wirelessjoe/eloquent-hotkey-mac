import AVFoundation
import Foundation
@preconcurrency import Speech

struct DictationConfiguration {
    let microphoneID: String?
    let silenceTimeout: TimeInterval
    let maxDuration: TimeInterval
}

final class DictationController: NSObject, @unchecked Sendable, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let configuration: DictationConfiguration
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
    private var sawSpeech = false
    private var isFinishing = false

    init(configuration: DictationConfiguration) {
        self.configuration = configuration
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
            if self.sawSpeech || !self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.finishWithCurrentTranscript()
            } else {
                self.finish(error: AppError.noSpeechDetected)
            }
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
            output.setSampleBufferDelegate(self, queue: engineQueue)

            guard captureSession.canAddOutput(output) else {
                throw AppError.unableToStartRecording("Could not receive audio from the selected microphone.")
            }
            captureSession.addOutput(output)
            captureSession.commitConfiguration()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
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
            self.sawSpeech = false
            self.isFinishing = false

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else {
                    return
                }

                self.engineQueue.async {
                    self.handleRecognition(result: result, error: error)
                }
            }

            startTimer()
            captureSession.startRunning()
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
            let transcript = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if transcript != latestTranscript {
                latestTranscript = transcript
                if !transcript.isEmpty {
                    sawSpeech = true
                    lastTranscriptChangeAt = Date()
                }
            }

            if result.isFinal {
                finishWithCurrentTranscript()
                return
            }
        }

        if let error {
            finish(error: error)
        }
    }

    private func evaluateStopConditions() {
        guard !isFinishing else {
            return
        }

        let now = Date()
        if sawSpeech && now.timeIntervalSince(lastTranscriptChangeAt) >= configuration.silenceTimeout {
            finishWithCurrentTranscript()
            return
        }

        if !sawSpeech && now.timeIntervalSince(startedAt) >= configuration.maxDuration {
            finish(error: AppError.noSpeechDetected)
            return
        }

        if now.timeIntervalSince(startedAt) >= configuration.maxDuration {
            finishWithCurrentTranscript()
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
        tearDown()
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func finish(error: Error) {
        guard !isFinishing else {
            return
        }

        isFinishing = true
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
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isFinishing, let request else {
            return
        }

        request.appendAudioSampleBuffer(sampleBuffer)
    }
}
