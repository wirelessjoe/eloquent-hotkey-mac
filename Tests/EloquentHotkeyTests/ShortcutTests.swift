import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import EloquentHotkey

final class ShortcutTests: XCTestCase {
    private let fnShortcut = Shortcut(keyCode: UInt16(kVK_Function), modifiers: [.function])

    func testSavedFnShortcutMatchesHardwarePressAndRelease() {
        XCTAssertTrue(fnShortcut.matchesPress(eventType: .flagsChanged, keyCode: 63, modifiers: [.function]))
        XCTAssertTrue(fnShortcut.matchesRelease(eventType: .flagsChanged, keyCode: 63, modifiers: []))
        XCTAssertFalse(fnShortcut.matchesRelease(eventType: .flagsChanged, keyCode: 63, modifiers: [.function]))
        XCTAssertFalse(fnShortcut.matchesPress(eventType: .flagsChanged, keyCode: 63, modifiers: []))
    }

    func testFnShortcutIgnoresOtherModifierTransitions() {
        XCTAssertFalse(fnShortcut.matchesPress(eventType: .flagsChanged, keyCode: UInt16(kVK_Shift), modifiers: [.function, .shift]))
        XCTAssertFalse(fnShortcut.matchesRelease(eventType: .flagsChanged, keyCode: UInt16(kVK_Shift), modifiers: []))
        XCTAssertFalse(fnShortcut.matchesPress(eventType: .keyDown, keyCode: 63, modifiers: [.function]))
    }

    func testRegularShortcutRequiresItsConfiguredModifiers() {
        let shortcut = Shortcut.defaultValue
        XCTAssertTrue(shortcut.matchesPress(eventType: .keyDown, keyCode: UInt16(kVK_Space), modifiers: [.control, .option]))
        XCTAssertFalse(shortcut.matchesPress(eventType: .keyDown, keyCode: UInt16(kVK_Space), modifiers: [.control]))
        XCTAssertFalse(shortcut.matchesPress(eventType: .keyDown, keyCode: UInt16(kVK_Space), modifiers: [.control, .option, .command]))
        XCTAssertFalse(shortcut.matchesPress(eventType: .keyDown, keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .option]))
    }

    func testReleaseStillMatchesWhenModifiersAreReleasedFirst() {
        XCTAssertTrue(Shortcut.defaultValue.matchesRelease(eventType: .keyUp, keyCode: UInt16(kVK_Space), modifiers: []))
        XCTAssertFalse(Shortcut.defaultValue.matchesRelease(eventType: .keyDown, keyCode: UInt16(kVK_Space), modifiers: []))
        XCTAssertFalse(Shortcut.defaultValue.matchesRelease(eventType: .keyUp, keyCode: UInt16(kVK_ANSI_V), modifiers: []))
    }

    func testCapsLockDoesNotChangeShortcutMatching() {
        let modifiers = Shortcut.normalizedModifiers(from: [.control, .option, .capsLock, .numericPad])
        XCTAssertTrue(Shortcut.defaultValue.matchesPress(eventType: .keyDown, keyCode: UInt16(kVK_Space), modifiers: modifiers))
    }
}
