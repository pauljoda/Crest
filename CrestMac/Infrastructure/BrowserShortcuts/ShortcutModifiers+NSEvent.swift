import AppKit
import Carbon.HIToolbox

extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: ShortcutModifiers = []
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        self = result
    }

    var appKitModifierFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.command) { result.insert(.command) }
        if contains(.option) { result.insert(.option) }
        if contains(.control) { result.insert(.control) }
        if contains(.shift) { result.insert(.shift) }
        return result
    }

    /// The modifiers as a system hot key names them.
    var carbonModifiers: UInt32 {
        var result = 0
        if contains(.command) { result |= cmdKey }
        if contains(.option) { result |= optionKey }
        if contains(.control) { result |= controlKey }
        if contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }
}
