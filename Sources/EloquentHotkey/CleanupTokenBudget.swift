struct CleanupTokenBudget: Sendable {
    // Leave room for message framing and the generated object's keys and punctuation.
    static let contextReserve = 64
    static let responseReserve = 32
    static let minimumResponseTokens = 64

    static func maximumResponseTokens(
        promptTokens: Int,
        instructionTokens: Int,
        schemaTokens: Int,
        contextSize: Int
    ) -> Int? {
        guard promptTokens > 0, instructionTokens >= 0, schemaTokens >= 0, contextSize > 0 else {
            return nil
        }

        var available = contextSize
        for count in [instructionTokens, schemaTokens, promptTokens, contextReserve] {
            guard count <= available else {
                return nil
            }
            available -= count
        }

        // If a complete copy of the input cannot fit, use local cleanup immediately
        // rather than spending time generating a truncated response.
        guard available >= minimumResponseTokens,
              promptTokens <= available - responseReserve else {
            return nil
        }

        // Allow modest expansion for corrected spelling and punctuation, not a rewrite.
        let expansion = promptTokens / 4 + (promptTokens % 4 == 0 ? 0 : 1)
        let desired = (promptTokens + responseReserve).addingReportingOverflow(expansion)
        return min(available, desired.overflow ? available : max(minimumResponseTokens, desired.partialValue))
    }

    static func conservativeTokenCount(for text: String) -> Int {
        // Token counting arrived in macOS 26.4. A byte bound keeps older systems
        // conservative for Unicode and technical text without assuming English.
        text.utf8.count
    }

    static func responseFitsBudget(outputTokens: Int, maximumResponseTokens: Int) -> Bool {
        // A response at the cap may be cut off even if guided generation returns
        // a valid Swift object. Keep the local transcript when completion is uncertain.
        outputTokens >= 0 && maximumResponseTokens > 0 && outputTokens < maximumResponseTokens
    }
}
