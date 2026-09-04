import AppKit
import Foundation

/// Maps a DOM `KeyboardEvent.code` to the macOS virtual key code AppKit needs
/// to build a real key event, and a DOM `key` to the characters that event
/// carries. A key WebKit cannot identify produces no navigation, no shortcut,
/// and no editing command, so a wrong code is a silently dead keystroke.
enum BrowserChromeDebuggerKeyCodes {
    /// `KeyboardEvent.code` to macOS virtual key code.
    static let virtualKeyCodes: [String: UInt16] = [
        "KeyA": 0x00, "KeyS": 0x01, "KeyD": 0x02, "KeyF": 0x03, "KeyH": 0x04, "KeyG": 0x05,
        "KeyZ": 0x06, "KeyX": 0x07, "KeyC": 0x08, "KeyV": 0x09, "KeyB": 0x0B, "KeyQ": 0x0C,
        "KeyW": 0x0D, "KeyE": 0x0E, "KeyR": 0x0F, "KeyY": 0x10, "KeyT": 0x11, "KeyO": 0x1F,
        "KeyU": 0x20, "KeyI": 0x22, "KeyP": 0x23, "KeyL": 0x25, "KeyJ": 0x26, "KeyK": 0x28,
        "KeyN": 0x2D, "KeyM": 0x2E,
        "Digit1": 0x12, "Digit2": 0x13, "Digit3": 0x14, "Digit4": 0x15, "Digit6": 0x16,
        "Digit5": 0x17, "Digit9": 0x19, "Digit7": 0x1A, "Digit8": 0x1C, "Digit0": 0x1D,
        "Equal": 0x18, "Minus": 0x1B, "BracketRight": 0x1E, "BracketLeft": 0x21,
        "Quote": 0x27, "Semicolon": 0x29, "Backslash": 0x2A, "Comma": 0x2B,
        "Slash": 0x2C, "Period": 0x2F, "Backquote": 0x32,
        "Enter": 0x24, "Tab": 0x30, "Space": 0x31, "Backspace": 0x33, "Escape": 0x35,
        "Delete": 0x75, "Home": 0x73, "End": 0x77, "PageUp": 0x74, "PageDown": 0x79,
        "ArrowLeft": 0x7B, "ArrowRight": 0x7C, "ArrowDown": 0x7D, "ArrowUp": 0x7E,
        "MetaLeft": 0x37, "MetaRight": 0x36, "ShiftLeft": 0x38, "ShiftRight": 0x3C,
        "CapsLock": 0x39, "AltLeft": 0x3A, "AltRight": 0x3D,
        "ControlLeft": 0x3B, "ControlRight": 0x3E, "Function": 0x3F,
        "NumpadDecimal": 0x41, "NumpadMultiply": 0x43, "NumpadAdd": 0x45, "NumLock": 0x47,
        "NumpadDivide": 0x4B, "NumpadEnter": 0x4C, "NumpadSubtract": 0x4E, "NumpadEqual": 0x51,
        "Numpad0": 0x52, "Numpad1": 0x53, "Numpad2": 0x54, "Numpad3": 0x55, "Numpad4": 0x56,
        "Numpad5": 0x57, "Numpad6": 0x58, "Numpad7": 0x59, "Numpad8": 0x5B, "Numpad9": 0x5C,
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60, "F6": 0x61,
        "F7": 0x62, "F8": 0x64, "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
    ]

    /// A DOM `key` that names an action rather than a character still travels as
    /// a character in an AppKit key event, using the same private-use values
    /// AppKit itself uses for the arrow and editing keys.
    static let namedKeyCharacters: [String: String] = [
        "Enter": "\r", "Tab": "\t", "Backspace": "\u{8}", "Escape": "\u{1B}",
        "Delete": String(UnicodeScalar(NSDeleteFunctionKey)!),
        "ArrowUp": String(UnicodeScalar(NSUpArrowFunctionKey)!),
        "ArrowDown": String(UnicodeScalar(NSDownArrowFunctionKey)!),
        "ArrowLeft": String(UnicodeScalar(NSLeftArrowFunctionKey)!),
        "ArrowRight": String(UnicodeScalar(NSRightArrowFunctionKey)!),
        "Home": String(UnicodeScalar(NSHomeFunctionKey)!),
        "End": String(UnicodeScalar(NSEndFunctionKey)!),
        "PageUp": String(UnicodeScalar(NSPageUpFunctionKey)!),
        "PageDown": String(UnicodeScalar(NSPageDownFunctionKey)!),
        "Space": " ",
    ]

    /// The modifier keys carry no text: sending one as a character would type
    /// the key's name into whatever holds focus.
    static let modifierCodes: Set<String> = [
        "ShiftLeft", "ShiftRight", "ControlLeft", "ControlRight", "AltLeft", "AltRight",
        "MetaLeft", "MetaRight", "CapsLock", "Function", "NumLock",
    ]

    static func virtualKeyCode(code: String?, key: String?) -> UInt16? {
        if let code, let value = virtualKeyCodes[code] { return value }
        guard let key else { return nil }
        if let value = virtualKeyCodes[key] { return value }
        guard key.count == 1, let scalar = key.unicodeScalars.first else { return nil }
        let upper = String(scalar).uppercased()
        if let value = virtualKeyCodes["Key" + upper] { return value }
        if scalar.value >= 48, scalar.value <= 57 { return virtualKeyCodes["Digit" + String(scalar)] }
        return nil
    }

    static func characters(text: String?, key: String?, code: String?) -> String {
        if let text, !text.isEmpty { return text }
        if let code, modifierCodes.contains(code) { return "" }
        if let key {
            if let named = namedKeyCharacters[key] { return named }
            if key.count == 1 { return key }
        }
        if let code, let named = namedKeyCharacters[code] { return named }
        return ""
    }

    /// CDP packs modifiers into one integer: 1 Alt, 2 Control, 4 Meta, 8 Shift.
    static func modifierFlags(_ value: Any?) throws -> NSEvent.ModifierFlags {
        guard let value else { return [] }
        let bits = try BrowserChromeDebuggerValues.integer(value, name: "modifiers")
        guard bits >= 0, bits < 16 else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("modifiers")
        }
        var flags: NSEvent.ModifierFlags = []
        if bits & 1 != 0 { flags.insert(.option) }
        if bits & 2 != 0 { flags.insert(.control) }
        if bits & 4 != 0 { flags.insert(.command) }
        if bits & 8 != 0 { flags.insert(.shift) }
        return flags
    }
}
