import AppKit
import Carbon
import CoreGraphics
import Foundation

struct Shortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    static let defaultValue = Shortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: [.control, .option]
    )

    private static let supportedModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
        .function,
    ]

    var displayString: String {
        var parts = ""
        if modifiers.contains(.control) {
            parts += "⌃"
        }
        if modifiers.contains(.option) {
            parts += "⌥"
        }
        if modifiers.contains(.shift) {
            parts += "⇧"
        }
        if modifiers.contains(.command) {
            parts += "⌘"
        }
        if modifiers.contains(.function), keyCode != UInt16(kVK_Function) {
            parts += "fn"
        }
        parts += KeyFormatter.name(for: keyCode)
        return parts
    }

    var isModifierOnly: Bool {
        KeyFormatter.isModifierOnlyKeyCode(keyCode)
    }

    static func from(event: NSEvent) -> Shortcut? {
        switch event.type {
        case .flagsChanged:
            return fromFlagsChanged(event)
        case .keyDown:
            return fromKeyDown(event)
        default:
            return nil
        }
    }

    func matchesPress(eventType: CGEventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        if isModifierOnly {
            return eventType == .flagsChanged
                && keyCode == self.keyCode
                && modifiers.contains(.function)
        }

        return eventType == .keyDown
            && keyCode == self.keyCode
            && modifiers == self.modifiers
    }

    func matchesRelease(eventType: CGEventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        if isModifierOnly {
            return eventType == .flagsChanged
                && keyCode == self.keyCode
                && !modifiers.contains(.function)
        }

        return eventType == .keyUp && keyCode == self.keyCode
    }

    static func normalizedModifiers(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(supportedModifiers)
    }

    private static func fromKeyDown(_ event: NSEvent) -> Shortcut? {
        guard !KeyFormatter.isModifierOnlyKeyCode(event.keyCode) else {
            return nil
        }

        let modifiers = normalizedModifiers(from: event.modifierFlags)
        guard !modifiers.isEmpty else {
            return nil
        }

        return Shortcut(
            keyCode: event.keyCode,
            modifiers: modifiers
        )
    }

    private static func fromFlagsChanged(_ event: NSEvent) -> Shortcut? {
        let modifiers = normalizedModifiers(from: event.modifierFlags)
        guard event.keyCode == UInt16(kVK_Function), modifiers.contains(.function) else {
            return nil
        }

        return Shortcut(
            keyCode: event.keyCode,
            modifiers: [.function]
        )
    }
}

enum KeyFormatter {
    private static let keyNames: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_LeftArrow): "Left Arrow",
        UInt16(kVK_RightArrow): "Right Arrow",
        UInt16(kVK_UpArrow): "Up Arrow",
        UInt16(kVK_DownArrow): "Down Arrow",
        UInt16(kVK_Function): "Fn",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
    ]

    static func name(for keyCode: UInt16) -> String {
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
    var onPress: (@Sendable () -> Void)?
    var onRelease: (@Sendable () -> Void)?
    var isEnabled = true

    private var shortcut: Shortcut?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isShortcutPressed = false

    deinit {
        unregister()
    }

    @discardableResult
    func register(shortcut: Shortcut) -> Bool {
        self.shortcut = shortcut
        isShortcutPressed = false
        return installEventTapIfNeeded()
    }

    func unregister() {
        shortcut = nil
        isShortcutPressed = false

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func installEventTapIfNeeded() -> Bool {
        if let eventTap, CFMachPortIsValid(eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return CGEvent.tapIsEnabled(tap: eventTap)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        eventTap = nil

        // A filtering tap needs event-posting access as well as keyboard access.
        guard PermissionManager.hasListenEventAccess(), PermissionManager.hasPostEventAccess() else {
            return false
        }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: Self.handleEventTap,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        return true
    }

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard let eventTap else {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled, let shortcut else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Shortcut.normalizedModifiers(
            from: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        )

        if shortcut.matchesPress(eventType: type, keyCode: keyCode, modifiers: modifiers) {
            if !isShortcutPressed {
                isShortcutPressed = true
                let handler = onPress
                DispatchQueue.main.async {
                    handler?()
                }
            }
            return nil
        }

        if isShortcutPressed, shortcut.matchesRelease(eventType: type, keyCode: keyCode, modifiers: modifiers) {
            isShortcutPressed = false
            let handler = onRelease
            DispatchQueue.main.async {
                handler?()
            }
            return nil
        }

        if isShortcutPressed,
           type == .keyDown || type == .flagsChanged,
           keyCode == shortcut.keyCode {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private static let handleEventTap: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let manager = Unmanaged<GlobalHotkeyManager>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        return manager.handle(proxy: proxy, type: type, event: event)
    }
}
