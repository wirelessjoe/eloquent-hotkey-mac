import ApplicationServices
import AVFoundation
import Foundation
import Speech

enum PermissionManager {
    static func requestMicrophoneAndSpeechAccess() async throws {
        try await requestMicrophoneAccessIfNeeded()
        try await requestSpeechAccessIfNeeded()
    }

    static func hasListenEventAccess(prompt: Bool = false) -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }

        guard prompt else {
            return false
        }

        return CGRequestListenEventAccess()
    }

    static func hasPostEventAccess(prompt: Bool = false) -> Bool {
        if CGPreflightPostEventAccess() {
            return true
        }

        guard prompt else {
            return false
        }

        return CGRequestPostEventAccess()
    }

    private static func requestMicrophoneAccessIfNeeded() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }

            guard granted else {
                throw AppError.microphoneDenied
            }
        case .denied, .restricted:
            throw AppError.microphoneDenied
        @unknown default:
            throw AppError.microphoneDenied
        }
    }

    private static func requestSpeechAccessIfNeeded() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            guard status == .authorized else {
                throw AppError.speechDenied
            }
        case .denied, .restricted:
            throw AppError.speechDenied
        @unknown default:
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
