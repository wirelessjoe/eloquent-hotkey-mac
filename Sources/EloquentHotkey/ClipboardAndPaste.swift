import AppKit
import ApplicationServices
import Foundation
import OSLog

@MainActor
enum ClipboardManager {
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    struct TemporaryWriteToken {
        let changeCount: Int
    }

    static func copy(_ text: String, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func snapshot(pasteboard: NSPasteboard = .general) -> Snapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []

        return Snapshot(items: items)
    }

    @discardableResult
    static func writeTemporarily(_ text: String, pasteboard: NSPasteboard = .general) -> TemporaryWriteToken? {
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            return nil
        }

        return TemporaryWriteToken(changeCount: pasteboard.changeCount)
    }

    static func restoreIfUnchanged(_ snapshot: Snapshot, token: TemporaryWriteToken, pasteboard: NSPasteboard = .general) {
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

@MainActor
protocol PasteDriver {
    var hasEventAccess: Bool { get }
    func focusTarget() async -> Bool
    func stageClipboard(_ text: String) -> Bool
    func postPasteCommand() async -> Bool
    func restoreClipboard(afterPaste: Bool)
}

@MainActor
enum AutoPasteController {
    private static var isPasting = false

    static func paste(_ text: String, into application: NSRunningApplication?) async -> Bool {
        await paste(text, using: SystemPasteDriver(application: application))
    }

    static func paste(_ text: String, using driver: any PasteDriver) async -> Bool {
        guard !isPasting, !text.isEmpty, !Task.isCancelled, driver.hasEventAccess else {
            return false
        }
        isPasting = true
        defer { isPasting = false }

        guard await driver.focusTarget(), !Task.isCancelled else {
            return false
        }
        guard driver.stageClipboard(text) else {
            driver.restoreClipboard(afterPaste: false)
            return false
        }

        let posted = await driver.postPasteCommand()
        driver.restoreClipboard(afterPaste: posted)
        return posted
    }
}

@MainActor
private final class SystemPasteDriver: PasteDriver {
    private static var pendingRestore: (snapshot: ClipboardManager.Snapshot, token: ClipboardManager.TemporaryWriteToken, task: Task<Void, Never>)?
    private let application: NSRunningApplication?
    private var snapshot: ClipboardManager.Snapshot?
    private var token: ClipboardManager.TemporaryWriteToken?
    private let logger = Logger(subsystem: "dev.codex.EloquentHotkey", category: "Paste")

    init(application: NSRunningApplication?) {
        self.application = application
    }

    var hasEventAccess: Bool { PermissionManager.hasPostEventAccess() }

    func focusTarget() async -> Bool {
        guard let application, !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            logger.error("Paste stopped: no external target application")
            return false
        }

        logger.notice("Preparing paste into \(application.bundleIdentifier ?? "unknown", privacy: .public)")
        if !isTargetFrontmost {
            application.unhide()
            _ = application.activate(options: [
                .activateAllWindows,
                .activateIgnoringOtherApps,
            ])
        }

        for _ in 0..<20 {
            if isTargetFrontmost {
                // Let a menu action dismiss before delivering a keyboard command.
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
                return isTargetFrontmost
            }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return false }
        }

        logger.error("Paste stopped: target application did not gain focus")
        return false
    }

    func stageClipboard(_ text: String) -> Bool {
        if let pending = Self.pendingRestore {
            pending.task.cancel()
            ClipboardManager.restoreIfUnchanged(pending.snapshot, token: pending.token)
            Self.pendingRestore = nil
        }
        snapshot = ClipboardManager.snapshot()
        token = ClipboardManager.writeTemporarily(text)
        return token != nil
    }

    func restoreClipboard(afterPaste: Bool) {
        guard let snapshot, let token else { return }
        if afterPaste {
            let task = Task { @MainActor in
                // Some apps request clipboard contents asynchronously after Cmd-V.
                // This delay never blocks completion of the paste operation.
                do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                ClipboardManager.restoreIfUnchanged(snapshot, token: token)
                Self.pendingRestore = nil
            }
            Self.pendingRestore = (snapshot, token, task)
        } else {
            ClipboardManager.restoreIfUnchanged(snapshot, token: token)
        }
    }

    func postPasteCommand() async -> Bool {
        guard hasEventAccess, isTargetFrontmost, !Task.isCancelled, let application else {
            logger.error("Paste stopped: permission or focus changed")
            return false
        }
        let keyCodeForV: CGKeyCode = 9
        let source = CGEventSource(stateID: .privateState)

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
        // Deliver directly to the confirmed destination, rather than routing
        // through global keyboard taps and whichever app becomes frontmost next.
        keyDown.postToPid(application.processIdentifier)
        try? await Task.sleep(for: .milliseconds(20))
        keyUp.postToPid(application.processIdentifier)

        logger.notice("Paste command delivered to pid \(application.processIdentifier)")
        return true
    }

    private var isTargetFrontmost: Bool {
        guard let application, !application.isTerminated else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
    }
}
