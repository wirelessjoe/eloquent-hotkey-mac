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
    typealias Refinement = @Sendable (String) async throws -> String?

    private let fallbackPolisher = TextPolisher()
    private let validator = TranscriptCleanupValidator()
    private let logger = Logger(subsystem: "dev.codex.EloquentHotkey", category: "Cleanup")
    private let refine: Refinement

    init(refine: Refinement? = nil) {
        self.refine = refine ?? { transcript in
            try await Self.refineWithAppleModel(transcript)
        }
    }

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
        // Prefer instant local polishing over model punctuation for short commands.
        // The validator only permits cosmetic changes when there is so little context.
        guard validator.requiresModelRefinement(for: fallback) else {
            return fallback
        }

        do {
            guard let refined = try await refine(fallback) else {
                logger.debug("Used local cleanup because model refinement was unavailable or would not fit in the context")
                return fallback
            }
            let polished = fallbackPolisher.polish(refined)
            if validator.accepts(polished, comparedTo: fallback) {
                logger.debug("Used Apple on-device transcript cleanup")
                return polished
            }

            logger.notice("Discarded Apple cleanup result because it removed or rewrote too much of the fallback transcript")
        } catch {
            logger.warning("Apple cleanup failed: \(error.localizedDescription, privacy: .public)")
        }

        return fallback
    }

    private static func refineWithAppleModel(_ transcript: String) async throws -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleTranscriptCleanupEngine.isUsable {
            return try await AppleTranscriptCleanupEngine.shared.clean(transcript)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable(description: "A minimally edited transcript cleanup result.")
private struct TranscriptCleanupResponse {
    let cleanedText: String
}

@available(macOS 26.0, *)
private actor AppleTranscriptCleanupEngine {
    static let shared = AppleTranscriptCleanupEngine()
    private static let model = SystemLanguageModel.default
    private var overheadTokenCounts: (instructions: Int, schema: Int)?
    private static let instructions = """
    You clean raw speech-to-text transcripts for a macOS dictation app.
    Return only the cleaned transcript text.
    Make minimal edits and preserve the speaker's wording and meaning.
    Fix punctuation, capitalization, and obvious speech-recognition mistakes.
    Preserve and correct developer and product names like GitHub, macOS, iOS, iPadOS, watchOS, visionOS, Swift, SwiftUI, Xcode, OpenAI, ChatGPT, JavaScript, TypeScript, GraphQL, PostgreSQL, API, URL, JSON, SQL, and CLI.
    Remove only obvious filler words or false starts.
    Do not add commentary, explanations, or markdown.
    \(CodingLexicon.cleanupGuidance)
    """

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

    func clean(_ transcript: String) async throws -> String? {
        let prompt = """
        Clean this transcript with minimal edits:

        \(transcript)
        """
        let overhead = try await tokenCountsForOverhead()
        let promptTokens: Int
        if #available(macOS 26.4, *) {
            promptTokens = try await Self.model.tokenCount(for: Prompt(prompt))
        } else {
            promptTokens = CleanupTokenBudget.conservativeTokenCount(for: prompt)
        }

        guard let maximumResponseTokens = CleanupTokenBudget.maximumResponseTokens(
            promptTokens: promptTokens,
            instructionTokens: overhead.instructions,
            schemaTokens: overhead.schema,
            contextSize: Self.model.contextSize
        ) else {
            return nil
        }

        let session = LanguageModelSession(model: Self.model, instructions: Self.instructions)
        let options = GenerationOptions(
            samplingMode: .greedy,
            temperature: nil,
            maximumResponseTokens: maximumResponseTokens
        )

        let response = try await session.respond(
            to: prompt,
            generating: TranscriptCleanupResponse.self,
            options: options
        )

        if #available(macOS 27.0, *),
           !CleanupTokenBudget.responseFitsBudget(
               outputTokens: response.usage.output.totalTokenCount,
               maximumResponseTokens: maximumResponseTokens
           ) {
            return nil
        }

        return response.content.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenCountsForOverhead() async throws -> (instructions: Int, schema: Int) {
        if let overheadTokenCounts {
            return overheadTokenCounts
        }

        let counts: (instructions: Int, schema: Int)
        if #available(macOS 26.4, *) {
            let instructions = try await Self.model.tokenCount(for: Instructions(Self.instructions))
            let schema = try await Self.model.tokenCount(for: TranscriptCleanupResponse.generationSchema)
            counts = (instructions, schema)
        } else {
            let instructions = CleanupTokenBudget.conservativeTokenCount(for: Self.instructions)
            let schema = try JSONEncoder().encode(TranscriptCleanupResponse.generationSchema).count
            counts = (instructions, schema)
        }
        // Instructions and schema are constant. Only tokenize the new prompt on
        // subsequent dictations, keeping token accounting off the repeated hot path.
        overheadTokenCounts = counts
        return counts
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
