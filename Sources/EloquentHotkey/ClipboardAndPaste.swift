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
        AXIsProcessTrusted()
    }

    static func paste(into application: NSRunningApplication?) async -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        if let application {
            application.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(for: .milliseconds(150))
        }

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
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
