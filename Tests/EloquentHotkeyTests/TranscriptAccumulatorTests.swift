import XCTest
@testable import EloquentHotkey

final class TranscriptAccumulatorTests: XCTestCase {
    func testKeepsLongerTranscriptWhenRecognizerShrinksToTail() {
        var accumulator = TranscriptAccumulator()

        let first = accumulator.ingest(
            formattedTranscript: "hello there this is a much longer message",
            segments: [
                segment(0.00, "hello"),
                segment(0.20, "there"),
                segment(0.40, "this"),
                segment(0.60, "is"),
                segment(0.80, "a"),
                segment(1.00, "much"),
                segment(1.20, "longer"),
                segment(1.40, "message"),
            ]
        )

        XCTAssertEqual(first.transcript, "hello there this is a much longer message")
        XCTAssertFalse(first.recognizerTranscriptShrank)

        let second = accumulator.ingest(
            formattedTranscript: "longer message",
            segments: [
                segment(1.20, "longer"),
                segment(1.40, "message"),
            ]
        )

        XCTAssertEqual(second.transcript, "hello there this is a much longer message")
        XCTAssertTrue(second.recognizerTranscriptShrank)
    }

    func testKeepsMissingMiddleChunkFromEarlierSegments() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "please commit the change and push to GitHub now",
            segments: [
                segment(0.00, "please"),
                segment(0.20, "commit"),
                segment(0.40, "the"),
                segment(0.60, "change"),
                segment(0.80, "and"),
                segment(1.00, "push"),
                segment(1.20, "to"),
                segment(1.40, "GitHub"),
                segment(1.60, "now"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "please commit and push to GitHub now",
            segments: [
                segment(0.00, "please"),
                segment(0.20, "commit"),
                segment(0.80, "and"),
                segment(1.00, "push"),
                segment(1.20, "to"),
                segment(1.40, "GitHub"),
                segment(1.60, "now"),
            ]
        )

        XCTAssertEqual(update.transcript, "please commit the change and push to GitHub now")
        XCTAssertTrue(update.recognizerTranscriptShrank)
    }

    func testLetsRevisedSegmentReplaceEarlierTextForSameTiming() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "ship it",
            segments: [
                segment(0.00, "ship"),
                segment(0.20, "it"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "shift it",
            segments: [
                segment(0.00, "shift"),
                segment(0.20, "it"),
            ]
        )

        XCTAssertEqual(update.transcript, "shift it")
        XCTAssertFalse(update.recognizerTranscriptShrank)
    }

    func testAllowsLongerFollowUpTranscriptWithoutDuplicatingWords() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "hello there",
            segments: [
                segment(0.00, "hello"),
                segment(0.20, "there"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "hello there this is new",
            segments: [
                segment(0.00, "hello"),
                segment(0.20, "there"),
                segment(0.40, "this"),
                segment(0.60, "is"),
                segment(0.80, "new"),
            ]
        )

        XCTAssertEqual(update.transcript, "hello there this is new")
        XCTAssertFalse(update.recognizerTranscriptShrank)
    }

    private func segment(_ timestamp: TimeInterval, _ text: String) -> TranscriptAccumulator.Segment {
        .init(timestamp: timestamp, duration: 0.18, text: text)
    }
}
