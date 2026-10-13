import XCTest
@testable import EloquentHotkey

@MainActor
final class TranscriptCleanerTests: XCTestCase {
    func testShortCommandIsPolishedWithoutCallingTheModel() async {
        let spy = RefinementSpy(response: "Unrelated text.")
        let cleaner = TranscriptCleaner(refine: { await spy.refine($0) })

        let result = await cleaner.clean("um open github")
        let inputs = await spy.inputs
        XCTAssertEqual(result, "Open GitHub.")
        XCTAssertTrue(inputs.isEmpty)
    }

    func testEmptyTranscriptDoesNotCallTheModel() async {
        let spy = RefinementSpy(response: "Unrelated text.")
        let cleaner = TranscriptCleaner(refine: { await spy.refine($0) })

        let result = await cleaner.clean("um")
        let inputs = await spy.inputs
        XCTAssertEqual(result, "")
        XCTAssertTrue(inputs.isEmpty)
    }

    func testLongerCommandStillUsesModelRefinement() async {
        let spy = RefinementSpy(response: nil)
        let cleaner = TranscriptCleaner(refine: { await spy.refine($0) })

        _ = await cleaner.clean("Please open the GitHub repo.")
        let original = "Please open the current GitHub repo."
        let result = await cleaner.clean(original)
        let inputs = await spy.inputs
        XCTAssertEqual(inputs, [original])
        XCTAssertEqual(result, original)
    }

    func testLongTranscriptIsLocallyPolishedBeforeRefinement() async {
        let expected = "Please update our current deployment config before lunch today."
        let spy = RefinementSpy(response: expected)
        let cleaner = TranscriptCleaner(refine: { await spy.refine($0) })

        let result = await cleaner.clean("um please update our current deployment config before lunch today")
        let inputs = await spy.inputs
        XCTAssertEqual(inputs, [expected])
        XCTAssertEqual(result, expected)
    }

    func testAcceptsAValidCorrectionAndPolishesTechnicalTerms() async {
        let cleaner = TranscriptCleaner(refine: { _ in
            "please update our existing deployment config with swift ui today"
        })

        let result = await cleaner.clean("Please update our current deployment config with SwiftUI today.")
        XCTAssertEqual(result, "Please update our existing deployment config with SwiftUI today.")
    }

    func testRejectsARefinementThatDropsNegation() async {
        let original = "Please do not deploy the current production build before lunch today."
        let cleaner = TranscriptCleaner(refine: { _ in
            "Please do deploy the current production build before lunch today."
        })

        let result = await cleaner.clean(original)
        XCTAssertEqual(result, original)
    }

    func testRejectsARefinementThatChangesANumber() async {
        let original = "Please send 12 copies of the deployment report before lunch today."
        let cleaner = TranscriptCleaner(refine: { _ in
            "Please send 21 copies of the deployment report before lunch today."
        })

        let result = await cleaner.clean(original)
        XCTAssertEqual(result, original)
    }

    func testRejectsSchemaInstructionsAppendedToALongTranscript() async {
        let original = Array(repeating: "Please update our current deployment config before lunch today.", count: 30)
            .joined(separator: " ")
        let cleaner = TranscriptCleaner(refine: { text in
            text + " Respond using the following JSON format: {\"type\": \"object\"}"
        })

        let result = await cleaner.clean(original)
        XCTAssertEqual(result, original)
    }

    func testKeepsTheLocalResultWhenRefinementIsSkippedOrFails() async {
        let original = "Please update our current deployment config before lunch today."
        let skipped = TranscriptCleaner(refine: { _ in nil })
        let failed = TranscriptCleaner(refine: { _ in throw RefinementError.failed })

        let skippedResult = await skipped.clean(original)
        let failedResult = await failed.clean(original)
        XCTAssertEqual(skippedResult, original)
        XCTAssertEqual(failedResult, original)
    }

    private enum RefinementError: Error {
        case failed
    }
}

private actor RefinementSpy {
    private(set) var inputs: [String] = []
    private let response: String?

    init(response: String?) {
        self.response = response
    }

    func refine(_ input: String) -> String? {
        inputs.append(input)
        return response
    }
}
