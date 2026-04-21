import XCTest
@testable import EloquentHotkey

final class TranscriptAccumulatorTests: XCTestCase {
    func testKeepsLongerTranscriptWhenRecognizerShrinksToTail() {
        var accumulator = TranscriptAccumulator()

        let first = accumulator.ingest(
            formattedTranscript: "hello there this is a much longer message",
            segments: [
                .init(timestamp: 0.0, duration: 0.2, text: "hello"),
                .init(timestamp: 0.2, duration: 0.2, text: "there"),
                .init(timestamp: 0.4, duration: 0.2, text: "this"),
                .init(timestamp: 0.6, duration: 0.2, text: "is"),
                .init(timestamp: 0.8, duration: 0.2, text: "a"),
                .init(timestamp: 1.0, duration: 0.2, text: "much"),
                .init(timestamp: 1.2, duration: 0.2, text: "longer"),
                .init(timestamp: 1.4, duration: 0.2, text: "message"),
            ]
        )

        XCTAssertEqual(first.transcript, "hello there this is a much longer message")
        XCTAssertFalse(first.recognizerTranscriptShrank)

        let second = accumulator.ingest(
            formattedTranscript: "longer message",
            segments: [
                .init(timestamp: 1.2, duration: 0.2, text: "longer"),
                .init(timestamp: 1.4, duration: 0.2, text: "message"),
            ]
        )

        XCTAssertEqual(second.transcript, "hello there this is a much longer message")
        XCTAssertTrue(second.recognizerTranscriptShrank)
    }

    func testMergesSegmentsAcrossCallbacks() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "hello there",
            segments: [
                .init(timestamp: 0.0, duration: 0.2, text: "hello"),
                .init(timestamp: 0.2, duration: 0.2, text: "there"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "this is new",
            segments: [
                .init(timestamp: 0.4, duration: 0.2, text: "this"),
                .init(timestamp: 0.6, duration: 0.2, text: "is"),
                .init(timestamp: 0.8, duration: 0.2, text: "new"),
            ]
        )

        XCTAssertEqual(update.transcript, "hello there this is new")
    }

    func testLetsRevisedSegmentReplaceEarlierTextForSameTiming() {
        var accumulator = TranscriptAccumulator()

        _ = accumulator.ingest(
            formattedTranscript: "ship it",
            segments: [
                .init(timestamp: 0.0, duration: 0.2, text: "ship"),
                .init(timestamp: 0.2, duration: 0.2, text: "it"),
            ]
        )

        let update = accumulator.ingest(
            formattedTranscript: "shift it",
            segments: [
                .init(timestamp: 0.0, duration: 0.2, text: "shift"),
                .init(timestamp: 0.2, duration: 0.2, text: "it"),
            ]
        )

        XCTAssertEqual(update.transcript, "shift it")
    }
}
