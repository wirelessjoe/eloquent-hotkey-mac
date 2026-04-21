import XCTest
@testable import EloquentHotkey

final class TextPolisherTests: XCTestCase {
    private let polisher = TextPolisher()

    func testRemovesCommonFillersAndNormalizesSpacing() {
        XCTAssertEqual(
            polisher.polish("um, i mean   this is   good"),
            "This is good."
        )
    }

    func testCapitalizesAfterSentenceBoundaries() {
        XCTAssertEqual(
            polisher.polish("hello. how are you? i am good"),
            "Hello. How are you? I am good."
        )
    }

    func testRemovesShortStuttersWithoutTouchingContentWords() {
        XCTAssertEqual(
            polisher.polish("I I think the the app is fast"),
            "I think the app is fast."
        )
    }

    func testTrimsDanglingPunctuationAfterCleanup() {
        XCTAssertEqual(
            polisher.polish("uh, hello there,"),
            "Hello there."
        )
    }

    func testNormalizesDeveloperProductNames() {
        XCTAssertEqual(
            polisher.polish("github on mac os with swift ui and open ai json api"),
            "GitHub on macOS with SwiftUI and OpenAI JSON API."
        )
    }
}
