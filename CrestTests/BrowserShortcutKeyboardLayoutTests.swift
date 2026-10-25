import AppKit
import Carbon
import XCTest

@testable import Crest

// MARK: - Types

/// An installed keyboard layout, read through its own key tables without
/// selecting it.
private struct KeyboardLayout {
    let id: String
    private let data: Data

    init?(_ id: String) {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard
            let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first,
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        self.id = id
        data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    }

    func press(_ keyCode: Int, _ modifiers: ShortcutModifiers) -> LayoutKeyPress {
        LayoutKeyPress(layout: self, keyCode: UInt16(keyCode), modifierFlags: modifiers.appKitModifierFlags)
    }

    /// What `keyCode` types with `modifiers`. A dead key types nothing as
    /// typed, and its accent when AppKit applies modifiers to it.
    func characters(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, accentingDeadKeys: Bool) -> String {
        var state: UInt32 = 0
        var carbon = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        let typed = translate(keyCode, modifierState: UInt32(carbon >> 8) & 0xFF, deadKeyState: &state)
        guard typed.isEmpty, state != 0, accentingDeadKeys else { return typed }
        return translate(UInt16(kVK_Space), modifierState: 0, deadKeyState: &state)
    }

    private func translate(_ keyCode: UInt16, modifierState: UInt32, deadKeyState: inout UInt32) -> String {
        data.withUnsafeBytes { bytes in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return "" }
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()), 0,
                &deadKeyState, characters.count, &length, &characters)
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}

/// A key press read through a layout's tables the way `NSEvent` reads one
/// through the current input source.
private struct LayoutKeyPress: BrowserShortcutKeyPress {
    let layout: KeyboardLayout
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags

    var charactersIgnoringModifiers: String? {
        layout.characters(keyCode, modifierFlags.intersection(.shift), accentingDeadKeys: false)
    }

    func characters(byApplyingModifiers modifiers: NSEvent.ModifierFlags) -> String? {
        layout.characters(keyCode, modifiers, accentingDeadKeys: true)
    }
}

/// A chord reads the key the menu bar matches. A layout whose ⌘ layer types
/// other characters, such as Dvorak – QWERTY ⌘ or Russian, reads a chord
/// with ⌘ from that layer, and every other layout reads it exactly as typed,
/// so shortcuts saved on those layouts keep their meaning.
final class BrowserShortcutKeyboardLayoutTests: XCTestCase {
    // MARK: - Actions - Reading

    func testStandardLayoutsReadEveryChordAsTyped() throws {
        let layouts = [
            "com.apple.keylayout.US", "com.apple.keylayout.ABC", "com.apple.keylayout.British",
            "com.apple.keylayout.Dvorak", "com.apple.keylayout.Colemak", "com.apple.keylayout.German",
            "com.apple.keylayout.French", "com.apple.keylayout.Swedish-Pro",
        ].compactMap(KeyboardLayout.init)
        try XCTSkipIf(layouts.isEmpty, "No standard keyboard layout is installed")
        let everyModifierSet = (0..<16).map(ShortcutModifiers.init(rawValue:))
        for layout in layouts {
            for keyCode in 0..<128 {
                for modifiers in everyModifierSet {
                    let press = layout.press(keyCode, modifiers)
                    XCTAssertEqual(
                        BrowserShortcutKey(event: press), Self.typedKey(press),
                        "\(layout.id) key \(keyCode) \(modifiers.rawValue)")
                }
            }
        }
    }

    @MainActor
    func testCommandLayerLayoutsRunTheCommandsTheMenuBarShows() throws {
        let layouts = [
            ("com.apple.keylayout.DVORAK-QWERTYCMD", Character("y")), ("com.apple.keylayout.Russian", "е"),
        ].compactMap { id, typedT in KeyboardLayout(id).map { ($0, typedT) } }
        try XCTSkipIf(layouts.isEmpty, "No keyboard layout with a ⌘ layer is installed")
        let store = BrowserShortcutStore()
        let commands: [(Int, ShortcutModifiers, ShortcutCommand?)] = [
            (kVK_ANSI_T, [.command], .newTab), (kVK_ANSI_T, [.command, .shift], .reopenClosedTab),
            (kVK_ANSI_W, [.command], .closeTabOrWindow), (kVK_ANSI_N, [.command], .newWindow),
            (kVK_ANSI_L, [.command], .openLocation), (kVK_ANSI_R, [.command], .reloadPage),
            (kVK_ANSI_F, [.command], .findInPage), (kVK_ANSI_X, [.command], nil),
        ]
        for (layout, typedT) in layouts {
            for (keyCode, modifiers, command) in commands {
                let shortcut = try XCTUnwrap(BrowserShortcut(event: layout.press(keyCode, modifiers)))
                XCTAssertEqual(
                    store.command(for: shortcut, isEnabled: { _ in true })?.name, command?.name,
                    "\(layout.id) key \(keyCode)")
            }
            let reads: [(Int, ShortcutModifiers, Character)] = [
                (kVK_ANSI_X, [.command], "x"), (kVK_ANSI_W, [.command], "w"), (kVK_ANSI_T, [.command, .option], "t"),
                (kVK_ANSI_LeftBracket, [.command, .shift], "{"), (kVK_ANSI_Equal, [.command, .shift], "+"),
                (kVK_ANSI_T, [.control], typedT),
            ]
            for (keyCode, modifiers, character) in reads {
                XCTAssertEqual(
                    BrowserShortcut(event: layout.press(keyCode, modifiers)),
                    BrowserShortcut(key: .character(character), modifiers: modifiers),
                    "\(layout.id) key \(keyCode) \(modifiers.rawValue)")
            }
        }
    }

    // MARK: - Actions - Support

    /// What the press read before layers were considered: as typed with only
    /// Shift, and a special key by its code.
    private static func typedKey(_ press: LayoutKeyPress) -> BrowserShortcutKey? {
        if let special = ShortcutSpecialKey(keyCode: press.keyCode) { return .special(special) }
        guard let characters = press.charactersIgnoringModifiers?.lowercased(), characters.count == 1,
            let character = characters.first, !character.isNewline, !character.isWhitespace
        else { return nil }
        return .character(character)
    }
}
