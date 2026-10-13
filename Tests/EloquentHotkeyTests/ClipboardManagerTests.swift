import AppKit
import XCTest
@testable import EloquentHotkey

@MainActor
final class ClipboardManagerTests: XCTestCase {
    func testRestoresOriginalTextAndOtherFormatsAfterTemporaryPaste() async throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("Original clipboard", forType: .string)
        let richText = Data("Original rich text".utf8)
        item.setData(richText, forType: .rtf)
        board.writeObjects([item])
        let snapshot = ClipboardManager.snapshot(pasteboard: board)
        let token = try XCTUnwrap(ClipboardManager.writeTemporarily("Dictation", pasteboard: board))
        XCTAssertEqual(board.string(forType: .string), "Dictation")
        ClipboardManager.restoreIfUnchanged(snapshot, token: token, pasteboard: board)
        XCTAssertEqual(board.string(forType: .string), "Original clipboard")
        XCTAssertEqual(board.data(forType: .rtf), richText)
    }

    func testDoesNotOverwriteSomethingCopiedDuringPaste() async throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        ClipboardManager.copy("Original", pasteboard: board)
        let snapshot = ClipboardManager.snapshot(pasteboard: board)
        let token = try XCTUnwrap(ClipboardManager.writeTemporarily("Dictation", pasteboard: board))
        ClipboardManager.copy("New user clipboard", pasteboard: board)
        ClipboardManager.restoreIfUnchanged(snapshot, token: token, pasteboard: board)
        XCTAssertEqual(board.string(forType: .string), "New user clipboard")
    }

    func testRestoresAnOriginallyEmptyClipboard() async throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        let snapshot = ClipboardManager.snapshot(pasteboard: board)
        let token = try XCTUnwrap(ClipboardManager.writeTemporarily("Dictation", pasteboard: board))
        ClipboardManager.restoreIfUnchanged(snapshot, token: token, pasteboard: board)
        XCTAssertNil(board.string(forType: .string))
    }
}
