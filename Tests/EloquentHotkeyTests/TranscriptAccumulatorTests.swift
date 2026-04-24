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

    func testRejectsWrappedDuplicatePrefixFromPreviousTranscript() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "Of course good morning guys what's next in this process we executed the docs from Morgan Stanley last Friday as well as yours of course",
            segments: [
                segment(0.00, "of"),
                segment(0.20, "course"),
                segment(0.40, "good"),
                segment(0.60, "morning"),
                segment(0.80, "guys"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "Good morning guys what's next in this process we executed the docs from Morgan Stanley last Friday as well as yours of course",
            segments: [
                segment(0.00, "good"),
                segment(0.20, "morning"),
                segment(0.40, "guys"),
                segment(0.60, "what's"),
                segment(0.80, "next"),
            ]
        )

        XCTAssertEqual(
            update.transcript,
            "Good morning guys what's next in this process we executed the docs from Morgan Stanley last Friday as well as yours of course"
        )
        XCTAssertFalse(update.recognizerTranscriptShrank)
    }

    func testKeepsEarlierFullCoverageWhenFinalSnapshotStartsLate() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "Good morning guys what's the next step in the process we executed Morgan Stanley docs on Friday and of course yours before that thanks",
            segments: [
                segment(0.00, "good"),
                segment(0.24, "morning"),
                segment(0.48, "guys"),
                segment(0.72, "what's"),
                segment(0.96, "the"),
                segment(1.20, "next"),
                segment(1.44, "step"),
                segment(1.68, "in"),
                segment(1.92, "the"),
                segment(2.16, "process"),
                segment(2.40, "we"),
                segment(2.64, "executed"),
                segment(2.88, "Morgan"),
                segment(3.12, "Stanley"),
                segment(3.36, "docs"),
                segment(3.60, "on"),
                segment(3.84, "Friday"),
                segment(4.08, "and"),
                segment(4.32, "of"),
                segment(4.56, "course"),
                segment(4.80, "yours"),
                segment(5.04, "before"),
                segment(5.28, "that"),
                segment(5.52, "thanks"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "We of course did yours before that thanks",
            segments: [
                segment(10.44, "we"),
                segment(10.68, "of"),
                segment(10.92, "course"),
                segment(11.16, "did"),
                segment(11.40, "yours"),
                segment(11.64, "before"),
                segment(11.88, "that"),
                segment(12.12, "thanks"),
            ]
        )

        XCTAssertEqual(
            update.transcript,
            "Good morning guys what's the next step in the process we executed Morgan Stanley docs on Friday and of course yours before that thanks"
        )
        XCTAssertTrue(update.recognizerTranscriptShrank)
    }

    func testDoesNotGraduallyDriftBestSnapshotForwardAcrossPartialUpdates() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "Good morning guys what's the next step in the process we executed Morgan Stanley docs on Friday and of course yours before that thanks",
            segments: [
                segment(0.00, "good"),
                segment(0.24, "morning"),
                segment(0.48, "guys"),
                segment(0.72, "what's"),
                segment(0.96, "the"),
                segment(1.20, "next"),
                segment(1.44, "step"),
                segment(1.68, "in"),
                segment(1.92, "the"),
                segment(2.16, "process"),
                segment(2.40, "we"),
                segment(2.64, "executed"),
                segment(2.88, "Morgan"),
                segment(3.12, "Stanley"),
                segment(3.36, "docs"),
                segment(3.60, "on"),
                segment(3.84, "Friday"),
                segment(4.08, "and"),
                segment(4.32, "of"),
                segment(4.56, "course"),
                segment(4.80, "yours"),
                segment(5.04, "before"),
                segment(5.28, "that"),
                segment(5.52, "thanks"),
            ]
        )

        _ = accumulator.ingest(
            formattedTranscript: "What's the next step in the process we executed Morgan Stanley docs on Friday and of course yours before that thanks",
            segments: [
                segment(0.72, "what's"),
                segment(0.96, "the"),
                segment(1.20, "next"),
                segment(1.44, "step"),
                segment(1.68, "in"),
                segment(1.92, "the"),
                segment(2.16, "process"),
                segment(2.40, "we"),
                segment(2.64, "executed"),
                segment(2.88, "Morgan"),
                segment(3.12, "Stanley"),
                segment(3.36, "docs"),
                segment(3.60, "on"),
                segment(3.84, "Friday"),
                segment(4.08, "and"),
                segment(4.32, "of"),
                segment(4.56, "course"),
                segment(4.80, "yours"),
                segment(5.04, "before"),
                segment(5.28, "that"),
                segment(5.52, "thanks"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "We executed Morgan Stanley docs on Friday and of course yours before that thanks",
            segments: [
                segment(2.40, "we"),
                segment(2.64, "executed"),
                segment(2.88, "Morgan"),
                segment(3.12, "Stanley"),
                segment(3.36, "docs"),
                segment(3.60, "on"),
                segment(3.84, "Friday"),
                segment(4.08, "and"),
                segment(4.32, "of"),
                segment(4.56, "course"),
                segment(4.80, "yours"),
                segment(5.04, "before"),
                segment(5.28, "that"),
                segment(5.52, "thanks"),
            ]
        )

        XCTAssertEqual(
            update.transcript,
            "Good morning guys what's the next step in the process we executed Morgan Stanley docs on Friday and of course yours before that thanks"
        )
        XCTAssertTrue(update.recognizerTranscriptShrank)
    }

    func testKeepsBestAnchoredCoverageWhenFinalFallsOutsideOpeningWindow() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "Good",
            segments: [
                segment(0.00, "good"),
            ]
        )

        _ = accumulator.ingest(
            formattedTranscript: "Good morning guys what's the next step in the process we executed Morgan Stanley docs on Friday and of course yours before that thanks",
            segments: [
                segment(0.72, "good"),
                segment(0.96, "morning"),
                segment(1.20, "guys"),
                segment(1.44, "what's"),
                segment(1.68, "the"),
                segment(1.92, "next"),
                segment(2.16, "step"),
                segment(2.40, "in"),
                segment(2.64, "the"),
                segment(2.88, "process"),
                segment(3.12, "we"),
                segment(3.36, "executed"),
                segment(3.60, "Morgan"),
                segment(3.84, "Stanley"),
                segment(4.08, "docs"),
                segment(4.32, "on"),
                segment(4.56, "Friday"),
                segment(4.80, "and"),
                segment(5.04, "of"),
                segment(5.28, "course"),
                segment(5.52, "yours"),
                segment(5.76, "before"),
                segment(6.00, "that"),
                segment(6.24, "thanks"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "That thanks",
            segments: [
                segment(10.08, "that"),
                segment(10.32, "thanks"),
            ]
        )

        XCTAssertEqual(
            update.transcript,
            "Good morning guys what's the next step in the process we executed Morgan Stanley docs on Friday and of course yours before that thanks"
        )
        XCTAssertTrue(update.recognizerTranscriptShrank)
    }

    private func segment(_ timestamp: TimeInterval, _ text: String) -> TranscriptAccumulator.Segment {
        .init(timestamp: timestamp, duration: 0.18, text: text)
    }
}
