import XCTest
@testable import EloquentHotkey

final class TranscriptCleanupValidatorTests: XCTestCase {
    private let validator = TranscriptCleanupValidator()
    private let original = "Please update our current deployment config before lunch today."

    func testAcceptsOneCorrectionWithoutDiscardingTheRemainingWords() {
        for (source, candidate) in [
            ("Plese update our current deployment config before lunch today.", original),
            (original, "Please update our existing deployment config before lunch today."),
            ("Please update the deployment config before the scheduled lauch.",
             "Please update the deployment config before the scheduled launch."),
        ] {
            XCTAssertTrue(validator.accepts(candidate, comparedTo: source), candidate)
        }
    }

    func testAcceptsOneInsertedWord() {
        XCTAssertTrue(validator.accepts(
            "Please update the current deployment config in repo before lunch today.",
            comparedTo: "Please update current deployment config in repo before lunch today."
        ))
    }

    func testAcceptsOneRemovedWord() {
        XCTAssertTrue(validator.accepts(
            "Please update our deployment config before lunch today.",
            comparedTo: original
        ))
    }

    func testRejectsMultipleCorrectionsWhenOnlyOneEditIsAllowed() {
        XCTAssertFalse(validator.accepts(
            "Kindly update our existing deployment config before lunch today.",
            comparedTo: original
        ))
        XCTAssertFalse(validator.accepts(
            "Please update our deployment config before lunch today, thanks.",
            comparedTo: original
        ))
    }

    func testAcceptsPunctuationAndCapitalizationChanges() {
        for (source, candidate) in [
            ("hello there", "Hello there!"),
            ("open github", "Open GitHub."),
            (original, "Please update our current deployment config, before lunch today!"),
            ("update origin/main", "Update origin/main."),
        ] {
            XCTAssertTrue(validator.accepts(candidate, comparedTo: source), candidate)
        }
    }

    func testRejectsContentChangesInShortCommands() {
        for (source, candidate) in [
            ("Do not deploy.", "Deploy now."),
            ("Ship it now.", "Ship it tomorrow."),
            ("Delete the old files.", "Keep the old files."),
            ("Cancel.", "Continue."),
        ] {
            XCTAssertFalse(validator.accepts(candidate, comparedTo: source), candidate)
        }
    }

    func testRejectsShortCommandReordering() {
        XCTAssertFalse(validator.accepts("Delete then copy.", comparedTo: "Copy then delete."))
    }

    func testRejectsRemovedNegationInLongTranscript() {
        let source = "Please do not deploy the current production build until we have reviewed all of the changes and run the full test suite together."
        XCTAssertFalse(validator.accepts(
            source.replacingOccurrences(of: "not ", with: ""),
            comparedTo: source
        ))
    }

    func testRejectsAddedOrReplacedNegation() {
        XCTAssertFalse(validator.accepts(
            "Please never update our current deployment config before lunch today.",
            comparedTo: original
        ))
        XCTAssertFalse(validator.accepts("Never deploy.", comparedTo: "Do not deploy."))
    }

    func testRejectsMovingNegationToADifferentAction() {
        XCTAssertFalse(validator.accepts(
            "Please deploy the current production build and do not run the full test suite until we have reviewed all of the changes together.",
            comparedTo: "Please do not deploy the current production build and run the full test suite until we have reviewed all of the changes together."
        ))
    }

    func testPreservesNegationWhenExpandingContractions() {
        for (source, candidate) in [
            ("Don't deploy.", "Do not deploy."),
            ("Don’t deploy.", "Do not deploy."),
            ("We can't deploy.", "We cannot deploy."),
            ("We won't deploy.", "We will not deploy."),
            ("It isn't ready.", "It is not ready."),
        ] {
            XCTAssertTrue(validator.accepts(candidate, comparedTo: source), candidate)
        }
    }

    func testRejectsRemovedContractedNegation() {
        XCTAssertFalse(validator.accepts("Do deploy.", comparedTo: "Don't deploy."))
        XCTAssertFalse(validator.accepts("We can deploy.", comparedTo: "We can’t deploy."))
    }

    func testRejectsChangedNumbersEvenInOtherwiseIdenticalLongText() {
        XCTAssertFalse(validator.accepts(
            "Please send 21 copies of the deployment report before lunch today.",
            comparedTo: "Please send 12 copies of the deployment report before lunch today."
        ))
    }

    func testRejectsDroppedOrReorderedNumbers() {
        XCTAssertFalse(validator.accepts("Send copies.", comparedTo: "Send 12 copies."))
        XCTAssertFalse(validator.accepts(
            "Please change the timeout from 30 to 10 seconds in the configuration.",
            comparedTo: "Please change the timeout from 10 to 30 seconds in the configuration."
        ))
    }

    func testRejectsChangedVersionNumbersAndDecimalAmounts() {
        XCTAssertFalse(validator.accepts("Install v3.", comparedTo: "Install v2."))
        XCTAssertFalse(validator.accepts("Send 15 dollars.", comparedTo: "Send 1.5 dollars."))
        XCTAssertFalse(validator.accepts("Send 1,5 dollars.", comparedTo: "Send 1.5 dollars."))
        XCTAssertFalse(validator.accepts("Meet at 9.30.", comparedTo: "Meet at 9:30."))
    }

    func testRejectsMajorRewritesTruncationAndCommentary() {
        for candidate in [
            "Make sure everything is ready for deployment this afternoon.",
            "Please update our current deployment config.",
            "Here is the cleaned transcript: " + original,
            original + " It is completely safe to deploy without checking anything.",
        ] {
            XCTAssertFalse(validator.accepts(candidate, comparedTo: original), candidate)
        }
    }

    func testRejectsCommentaryAndSchemaEchoesEvenOnLongDictations() {
        let source = Array(repeating: original, count: 60).joined(separator: " ")
        for candidate in [
            "Here is the cleaned transcript: " + source,
            source + " This is the cleaned transcript.",
            source + " Respond using the following JSON format: {\"type\": \"object\"}",
        ] {
            XCTAssertFalse(validator.accepts(candidate, comparedTo: source))
        }
        let corrected = source.replacingOccurrences(of: "current", with: "existing")
        XCTAssertFalse(validator.accepts(
            corrected + " Respond using the following JSON format: {\"type\": \"object\"}",
            comparedTo: source
        ))
    }

    func testAllowsSchemaInstructionsThatWereActuallyDictated() {
        let source = "Respond using the following JSON format: type object."
        XCTAssertTrue(validator.accepts(source, comparedTo: source))
    }

    func testRejectsEmptyAndPunctuationOnlyResults() {
        for candidate in ["", " ", "...", "''"] {
            XCTAssertFalse(validator.accepts(candidate, comparedTo: original))
        }
        XCTAssertFalse(validator.accepts("Hello.", comparedTo: ""))
        XCTAssertFalse(validator.accepts("...", comparedTo: "..."))
        XCTAssertFalse(validator.accepts("''", comparedTo: "''"))
    }

    func testAcceptsSmallCorrectionsInLongDictation() {
        let source = Array(repeating: original, count: 60).joined(separator: " ")
        let candidate = source.replacingOccurrences(of: "current", with: "existing")
        XCTAssertTrue(validator.accepts(candidate, comparedTo: source))
        XCTAssertFalse(validator.accepts(String(source.prefix(source.count / 2)), comparedTo: source))
    }
}
