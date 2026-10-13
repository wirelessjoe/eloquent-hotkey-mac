import XCTest
@testable import EloquentHotkey

final class CleanupTokenBudgetTests: XCTestCase {
    func testShortTranscriptKeepsASmallResponseAllowance() {
        XCTAssertEqual(budget(prompt: 10), 64)
    }

    func testLongTranscriptIsNotCappedAt256Tokens() {
        let limit = budget(prompt: 400)
        XCTAssertEqual(limit, 532)
        XCTAssertGreaterThan(limit ?? 0, 256)
    }

    func testAllowsExpansionForPunctuationAndStructuredOutput() {
        XCTAssertEqual(budget(prompt: 101), 159)
    }

    func testCapsExpansionToTheRemainingContext() {
        // 326 - 20 instructions - 10 schema - 100 prompt - 64 framing = 132.
        XCTAssertEqual(budget(prompt: 100, instructions: 20, schema: 10, context: 326), 132)
    }

    func testSkipsModelWhenACompleteResponseWouldNotFit() {
        XCTAssertNil(budget(prompt: 100, instructions: 20, schema: 10, context: 325))
    }

    func testAccountsForBothInstructionsAndSchema() {
        XCTAssertNil(budget(prompt: 100, instructions: 21, schema: 10, context: 326))
        XCTAssertNil(budget(prompt: 100, instructions: 20, schema: 11, context: 326))
    }

    func testReservesMessageFramingAndMinimumResponseSpace() {
        XCTAssertEqual(budget(prompt: 1, instructions: 0, schema: 0, context: 129), 64)
        XCTAssertNil(budget(prompt: 1, instructions: 0, schema: 0, context: 128))
    }

    func testUsesTheActualModelContextSize() {
        XCTAssertNil(budget(prompt: 1_900, instructions: 250, schema: 50, context: 4_096))
        XCTAssertEqual(budget(prompt: 1_900, instructions: 250, schema: 50, context: 8_192), 2_407)
    }

    func testSkipsOversizedPromptsAndOverhead() {
        XCTAssertNil(budget(prompt: 5_000))
        XCTAssertNil(budget(prompt: 10, instructions: 5_000))
        XCTAssertNil(budget(prompt: 10, schema: 5_000))
    }

    func testRejectsInvalidCountsWithoutReturningANegativeLimit() {
        XCTAssertNil(budget(prompt: 0))
        XCTAssertNil(budget(prompt: -1))
        XCTAssertNil(budget(prompt: 10, instructions: -1))
        XCTAssertNil(budget(prompt: 10, schema: -1))
        XCTAssertNil(budget(prompt: 10, context: 0))
        XCTAssertNil(budget(prompt: Int.max, context: Int.max))
    }

    func testOlderSystemsUseAConservativeUnicodeEstimate() {
        XCTAssertEqual(CleanupTokenBudget.conservativeTokenCount(for: "Hello"), 5)
        XCTAssertEqual(CleanupTokenBudget.conservativeTokenCount(for: "你好"), 6)
        XCTAssertEqual(CleanupTokenBudget.conservativeTokenCount(for: "💻"), 4)
    }

    func testRejectsAResponseThatExhaustsItsTokenAllowance() {
        XCTAssertTrue(CleanupTokenBudget.responseFitsBudget(outputTokens: 474, maximumResponseTokens: 475))
        XCTAssertFalse(CleanupTokenBudget.responseFitsBudget(outputTokens: 475, maximumResponseTokens: 475))
        XCTAssertFalse(CleanupTokenBudget.responseFitsBudget(outputTokens: 480, maximumResponseTokens: 475))
        XCTAssertFalse(CleanupTokenBudget.responseFitsBudget(outputTokens: -1, maximumResponseTokens: 475))
        XCTAssertFalse(CleanupTokenBudget.responseFitsBudget(outputTokens: 1, maximumResponseTokens: 0))
    }

    private func budget(
        prompt: Int,
        instructions: Int = 300,
        schema: Int = 50,
        context: Int = 4_096
    ) -> Int? {
        CleanupTokenBudget.maximumResponseTokens(
            promptTokens: prompt,
            instructionTokens: instructions,
            schemaTokens: schema,
            contextSize: context
        )
    }
}
