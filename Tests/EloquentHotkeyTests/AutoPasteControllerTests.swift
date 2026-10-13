import XCTest
@testable import EloquentHotkey

@MainActor
final class AutoPasteControllerTests: XCTestCase {
    func testMissingPermissionDoesNotChangeClipboardOrSendKeys() async {
        let driver = StubPasteDriver()
        driver.hasEventAccess = false
        let pasted = await AutoPasteController.paste("Dictation", using: driver)
        XCTAssertFalse(pasted)
        XCTAssertTrue(driver.operations.isEmpty)
    }

    func testFailedFocusDoesNotChangeClipboardOrSendKeys() async {
        let driver = StubPasteDriver()
        driver.canFocus = false
        let pasted = await AutoPasteController.paste("Dictation", using: driver)
        XCTAssertFalse(pasted)
        XCTAssertEqual(driver.operations, ["focus"])
    }

    func testSuccessfulPasteWaitsForFocusAndDefersRestoration() async {
        let driver = StubPasteDriver()
        let pasted = await AutoPasteController.paste("Dictation", using: driver)
        XCTAssertTrue(pasted)
        XCTAssertEqual(driver.stagedText, "Dictation")
        XCTAssertEqual(driver.operations, ["focus", "stage", "post", "restore after paste"])
    }

    func testFailedPostRestoresClipboardImmediately() async {
        let driver = StubPasteDriver()
        driver.canPost = false
        let pasted = await AutoPasteController.paste("Dictation", using: driver)
        XCTAssertFalse(pasted)
        XCTAssertEqual(driver.operations, ["focus", "stage", "post", "restore immediately"])
    }

    func testFailedClipboardWriteDoesNotPost() async {
        let driver = StubPasteDriver()
        driver.canStage = false
        let pasted = await AutoPasteController.paste("Dictation", using: driver)
        XCTAssertFalse(pasted)
        XCTAssertEqual(driver.operations, ["focus", "stage", "restore immediately"])
    }

    func testEmptyTextDoesNotChangeClipboardOrSendKeys() async {
        let driver = StubPasteDriver()
        let pasted = await AutoPasteController.paste("", using: driver)
        XCTAssertFalse(pasted)
        XCTAssertTrue(driver.operations.isEmpty)
    }

    func testCancelledPasteDoesNotChangeClipboardOrSendKeys() async {
        let driver = StubPasteDriver()
        let task = Task { await AutoPasteController.paste("Dictation", using: driver) }
        task.cancel()
        let pasted = await task.value
        XCTAssertFalse(pasted)
        XCTAssertTrue(driver.operations.isEmpty)
    }

    func testOverlappingPasteCannotReplaceStagedClipboard() async {
        let first = StubPasteDriver()
        first.pauseFocus = true
        let firstTask = Task { await AutoPasteController.paste("First", using: first) }
        while first.focusContinuation == nil { await Task.yield() }
        let second = StubPasteDriver()
        let secondResult = await AutoPasteController.paste("Second", using: second)
        XCTAssertFalse(secondResult)
        XCTAssertTrue(second.operations.isEmpty)
        first.focusContinuation?.resume(returning: true)
        let firstResult = await firstTask.value
        XCTAssertTrue(firstResult)
        XCTAssertEqual(first.stagedText, "First")
    }
}

@MainActor
private final class StubPasteDriver: PasteDriver {
    var hasEventAccess = true
    var canFocus = true
    var canStage = true
    var canPost = true
    var pauseFocus = false
    var focusContinuation: CheckedContinuation<Bool, Never>?
    var operations: [String] = []
    var stagedText: String?

    func focusTarget() async -> Bool {
        operations.append("focus")
        if pauseFocus {
            return await withCheckedContinuation { focusContinuation = $0 }
        }
        return canFocus
    }

    func stageClipboard(_ text: String) -> Bool {
        operations.append("stage")
        stagedText = text
        return canStage
    }

    func postPasteCommand() async -> Bool {
        operations.append("post")
        return canPost
    }

    func restoreClipboard(afterPaste: Bool) {
        operations.append(afterPaste ? "restore after paste" : "restore immediately")
    }
}
