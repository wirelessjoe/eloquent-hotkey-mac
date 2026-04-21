import AppKit
import Carbon
import Foundation

struct Shortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let defaultValue = Shortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey) | UInt32(optionKey)
    )

    static func from(event: NSEvent) -> Shortcut? {
        let supportedFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !supportedFlags.isEmpty else {
            return nil
        }

        if KeyFormatter.isModifierOnlyKeyCode(event.keyCode) {
            return nil
        }

        var modifiers: UInt32 = 0
        if supportedFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if supportedFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if supportedFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if supportedFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }

        return Shortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
    }

    var displayString: String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 {
            parts += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts += "⌘"
        }
        parts += KeyFormatter.name(for: keyCode)
        return parts
    }
}

enum KeyFormatter {
    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_LeftArrow): "Left Arrow",
        UInt32(kVK_RightArrow): "Right Arrow",
        UInt32(kVK_UpArrow): "Up Arrow",
        UInt32(kVK_DownArrow): "Down Arrow",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
    ]

    static func name(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    static func isModifierOnlyKeyCode(_ keyCode: UInt16) -> Bool {
        [
            UInt16(kVK_Command),
            UInt16(kVK_RightCommand),
            UInt16(kVK_Shift),
            UInt16(kVK_RightShift),
            UInt16(kVK_Option),
            UInt16(kVK_RightOption),
            UInt16(kVK_Control),
            UInt16(kVK_RightControl),
            UInt16(kVK_Function),
            UInt16(kVK_CapsLock),
        ].contains(keyCode)
    }
}

final class GlobalHotkeyManager {
    var onKeyPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init() {
        installHandlerIfNeeded()
    }

    deinit {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @discardableResult
    func register(shortcut: Shortcut) -> Bool {
        unregister()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("ELQT"),
            id: 1
        )

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            return false
        }

        self.hotKeyRef = hotKeyRef
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let manager = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.onKeyPress?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { partial, character in
            (partial << 8) + OSType(character)
        }
    }
}
