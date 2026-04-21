import AppKit
import ApplicationServices
import Foundation

enum ClipboardManager {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

enum AutoPasteController {
    static var isAccessibilityTrusted: Bool {
        PermissionManager.hasPostEventAccess()
    }

    static func paste(into application: NSRunningApplication?) async -> Bool {
        guard PermissionManager.hasPostEventAccess() else {
            return false
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
