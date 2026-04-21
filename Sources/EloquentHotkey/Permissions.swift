import AVFoundation
import Foundation
import Speech

enum PermissionManager {
    static func requestMicrophoneAndSpeechAccess() async throws {
        let microphoneGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        guard microphoneGranted else {
            throw AppError.microphoneDenied
        }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            throw AppError.speechDenied
        }
    }
}

enum AppError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case microphoneUnavailable
    case unableToStartRecording(String)
    case noSpeechDetected
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access was denied. Allow microphone access in System Settings."
        case .speechDenied:
            return "Speech recognition access was denied. Allow speech recognition in System Settings."
        case .recognizerUnavailable:
            return "English speech recognition is unavailable right now."
        case .microphoneUnavailable:
            return "The selected microphone is unavailable. Choose another microphone in Settings."
        case .unableToStartRecording(let reason):
            return "Could not start dictation: \(reason)"
        case .noSpeechDetected:
            return "No speech was detected."
        case .emptyTranscript:
            return "No text was captured from the recording."
        }
    }
}
