import AppKit
import ApplicationServices
import Foundation

enum ClipboardManager {
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    struct TemporaryWriteToken {
        let changeCount: Int
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func snapshot() -> Snapshot {
        let pasteboard = NSPasteboard.general
        let items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []

        return Snapshot(items: items)
    }

    @discardableResult
    static func writeTemporarily(_ text: String) -> TemporaryWriteToken? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            return nil
        }

        return TemporaryWriteToken(changeCount: pasteboard.changeCount)
    }

    static func restoreIfUnchanged(_ snapshot: Snapshot, token: TemporaryWriteToken) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == token.changeCount else {
            return
        }

        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else {
            return
        }

        let restoredItems = snapshot.items.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}

enum AutoPasteController {
    static var isAccessibilityTrusted: Bool {
        PermissionManager.hasPostEventAccess()
    }

    static func paste(_ text: String, into application: NSRunningApplication?) async -> Bool {
        guard PermissionManager.hasPostEventAccess() else {
            return false
        }

        let snapshot = ClipboardManager.snapshot()
        guard let token = ClipboardManager.writeTemporarily(text) else {
            return false
        }

        defer {
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                ClipboardManager.restoreIfUnchanged(snapshot, token: token)
            }
        }

        try? await Task.sleep(for: .milliseconds(120))

        if let application {
            application.unhide()
            _ = application.activate(options: [
                .activateAllWindows,
                .activateIgnoringOtherApps,
            ])

            for _ in 0..<12 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                    break
                }

                try? await Task.sleep(for: .milliseconds(60))
            }
        }

        return await postPasteCommand()
    }

    private static func postPasteCommand() async -> Bool {
        let keyCodeForV: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCodeForV,
            keyDown: true
        ),
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCodeForV,
            keyDown: false
        ) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(20))
        keyUp.post(tap: .cghidEventTap)

        return true
    }
}
