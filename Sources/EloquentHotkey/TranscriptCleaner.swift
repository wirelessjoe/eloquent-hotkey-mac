import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

struct CleanupEngineStatus: Sendable, Equatable {
    let headline: String
    let detail: String
    let isAppleIntelligenceActive: Bool
}

actor TranscriptCleaner {
    private let fallbackPolisher = TextPolisher()
    private let logger = Logger(subsystem: "dev.codex.EloquentHotkey", category: "Cleanup")

    static func currentStatus() -> CleanupEngineStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            AppleTranscriptCleanupEngine.status
        } else {
            CleanupEngineStatus(
                headline: "Fast local cleanup",
                detail: "This build includes Apple cleanup support, but this Mac is running an older macOS release, so the instant local fallback is active.",
                isAppleIntelligenceActive: false
            )
        }
        #else
        CleanupEngineStatus(
            headline: "Fast local cleanup",
            detail: "This build does not include Apple Intelligence cleanup support, so the instant local fallback is active.",
            isAppleIntelligenceActive: false
        )
        #endif
    }

    func clean(_ rawText: String) async -> String {
        let fallback = fallbackPolisher.polish(rawText)
        guard !fallback.isEmpty else {
            return fallback
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleTranscriptCleanupEngine.isUsable {
            do {
                let refined = try await AppleTranscriptCleanupEngine.clean(fallback)
                let polished = fallbackPolisher.polish(refined)
                if looksReasonable(polished, comparedTo: fallback) {
                    logger.debug("Used Apple on-device transcript cleanup")
                    return polished
                }

                logger.notice("Discarded Apple cleanup result because it removed or rewrote too much of the fallback transcript")
            } catch {
                logger.warning("Apple cleanup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif

        return fallback
    }

    private func looksReasonable(_ cleaned: String, comparedTo fallback: String) -> Bool {
        guard !cleaned.isEmpty else {
            return false
        }

        let ratio = Double(cleaned.count) / Double(max(fallback.count, 1))
        let fallbackWords = Self.normalizedWords(in: fallback)
        guard fallbackWords.count >= 6 else {
            return ratio >= 0.4 && ratio <= 1.6
        }

        guard ratio >= 0.8 && ratio <= 1.25 else {
            return false
        }

        let cleanedWords = Self.normalizedWords(in: cleaned)
        guard cleanedWords.count >= max(fallbackWords.count - 2, 1) else {
            return false
        }

        let retention = Self.orderedWordRetention(reference: fallbackWords, candidate: cleanedWords)
        return retention >= 0.88
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

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable(description: "A minimally edited transcript cleanup result.")
private struct TranscriptCleanupResponse {
    let cleanedText: String
}

@available(macOS 26.0, *)
private enum AppleTranscriptCleanupEngine {
    private static let model = SystemLanguageModel.default

    static var isUsable: Bool {
        model.isAvailable && (model.supportsLocale(Locale(identifier: "en_US")) || model.supportsLocale(.current))
    }

    static var status: CleanupEngineStatus {
        let localeDescription = supportedLocaleDescription
        switch model.availability {
        case .available:
            guard isUsable else {
                return CleanupEngineStatus(
                    headline: "Fast local cleanup",
                    detail: "Apple Intelligence is available on this Mac, but the on-device model does not support \(localeDescription), so the instant local fallback is active.",
                    isAppleIntelligenceActive: false
                )
            }

            return CleanupEngineStatus(
                headline: "Apple Intelligence cleanup active",
                detail: "This build is using Apple's on-device cleanup model on this Mac.",
                isAppleIntelligenceActive: true
            )
        case .unavailable(let reason):
            return CleanupEngineStatus(
                headline: "Fast local cleanup",
                detail: detail(for: reason),
                isAppleIntelligenceActive: false
            )
        }
    }

    static func clean(_ transcript: String) async throws -> String {
        let session = LanguageModelSession(model: model) {
            """
            You clean raw speech-to-text transcripts for a macOS dictation app.
            Return only the cleaned transcript text.
            Make minimal edits and preserve the speaker's wording and meaning.
            Fix punctuation, capitalization, and obvious speech-recognition mistakes.
            Preserve and correct developer and product names like GitHub, macOS, iOS, iPadOS, watchOS, visionOS, Swift, SwiftUI, Xcode, OpenAI, ChatGPT, JavaScript, TypeScript, GraphQL, PostgreSQL, API, URL, JSON, SQL, and CLI.
            Remove only obvious filler words or false starts.
            Do not add commentary, explanations, or markdown.
            \(CodingLexicon.cleanupGuidance)
            """
        }

        let options = GenerationOptions(
            sampling: .greedy,
            temperature: nil,
            maximumResponseTokens: recommendedMaximumResponseTokens(for: transcript)
        )

        let response = try await session.respond(
            to: """
            Clean this transcript with minimal edits:

            \(transcript)
            """,
            generating: TranscriptCleanupResponse.self,
            options: options
        )

        return response.content.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func recommendedMaximumResponseTokens(for transcript: String) -> Int {
        max(64, min(256, transcript.count / 2))
    }

    private static var supportedLocaleDescription: String {
        let preferredLocales = [Locale.current, Locale(identifier: "en_US")]
        if let locale = preferredLocales.first(where: { model.supportsLocale($0) }) {
            return locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        }

        return Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier
    }

    private static func detail(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This build supports Apple cleanup, but this Mac does not support Apple Intelligence, so the instant local fallback is active."
        case .appleIntelligenceNotEnabled:
            return "This build supports Apple cleanup, but Apple Intelligence is turned off on this Mac, so the instant local fallback is active."
        case .modelNotReady:
            return "This build supports Apple cleanup, but the Apple Intelligence model is not ready yet on this Mac. The instant local fallback is active for now."
        @unknown default:
            return "This build supports Apple cleanup, but the Apple Intelligence model is unavailable on this Mac right now, so the instant local fallback is active."
        }
    }
}
#endif
