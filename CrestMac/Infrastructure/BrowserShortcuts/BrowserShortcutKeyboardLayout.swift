import Carbon
import Foundation

/// A keyboard layout read through its own key tables.
struct BrowserShortcutKeyboardLayout {
    // MARK: - Variables

    private let data: Data

    /// The layout the person types with now, or nil when the input source
    /// has no key tables.
    static var current: BrowserShortcutKeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return BrowserShortcutKeyboardLayout(
            data: Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data)
    }

    /// Each digit key: the symbol Shift types on it, as a shortcut saved it,
    /// and the digit it types alone. A key that types its digit with Shift
    /// too, such as the keypad's, has nothing to rename.
    var shiftedDigits: [ShiftedDigit] {
        (0..<128).compactMap { keyCode in
            let digit = characters(UInt16(keyCode), shift: false)
            guard digit.count == 1, digit.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
            let symbol = characters(UInt16(keyCode), shift: true).lowercased()
            guard symbol.count == 1, symbol != digit else { return nil }
            return ShiftedDigit(symbol: symbol, digit: digit)
        }
    }

    // MARK: - Initializers

    private init(data: Data) {
        self.data = data
    }

    // MARK: - Actions - Reading

    /// What `keyCode` types alone or with Shift, with no dead key pending.
    private func characters(_ keyCode: UInt16, shift: Bool) -> String {
        data.withUnsafeBytes { bytes in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return "" }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let modifierState = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
            UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length, &characters)
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
