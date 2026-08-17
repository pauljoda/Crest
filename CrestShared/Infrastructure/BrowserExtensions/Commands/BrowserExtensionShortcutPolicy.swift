import Foundation
import Observation

enum BrowserExtensionShortcutPolicy {
    static func activationKey(for key: BrowserShortcutKey) -> String? {
        switch key {
        case .character(let character):
            let value = String(character).lowercased()
            guard value.count == 1,
                let scalar = value.unicodeScalars.first,
                CharacterSet.alphanumerics.contains(scalar)
                    || value == ","
                    || value == "."
                    || value == " "
            else {
                return nil
            }
            return value
        case .special(let key):
            if key == .space { return " " }
            guard let scalarValue = specialScalar(for: key),
                let scalar = UnicodeScalar(scalarValue)
            else {
                return nil
            }
            return String(Character(scalar))
        }
    }

    static func shortcut(
        activationKey: String?,
        modifiers: BrowserShortcutModifiers
    ) -> BrowserShortcut? {
        guard let activationKey,
            modifiers.isEmpty == false,
            let key = key(for: activationKey)
        else {
            return nil
        }
        return BrowserShortcut(key: key, modifiers: modifiers)
    }

    private static func key(for activationKey: String) -> BrowserShortcutKey? {
        guard activationKey.count == 1,
            let character = activationKey.first
        else { return nil }
        let scalarValue = character.unicodeScalars.first?.value
        if activationKey == " " {
            return .special(.space)
        }
        if let scalarValue,
            let special = specialKey(for: scalarValue)
        {
            return .special(special)
        }
        let normalized = activationKey.lowercased()
        guard normalized.count == 1,
            let character = normalized.first
        else { return nil }
        return .character(character)
    }

    private static func specialScalar(
        for key: BrowserShortcutSpecialKey
    ) -> UInt32? {
        switch key {
        case .upArrow: 0xF700
        case .downArrow: 0xF701
        case .leftArrow: 0xF702
        case .rightArrow: 0xF703
        case .f1: 0xF704
        case .f2: 0xF705
        case .f3: 0xF706
        case .f4: 0xF707
        case .f5: 0xF708
        case .f6: 0xF709
        case .f7: 0xF70A
        case .f8: 0xF70B
        case .f9: 0xF70C
        case .f10: 0xF70D
        case .f11: 0xF70E
        case .f12: 0xF70F
        case .forwardDelete: 0xF728
        case .home: 0xF729
        case .end: 0xF72B
        case .pageUp: 0xF72C
        case .pageDown: 0xF72D
        case .tab, .escape, .returnKey, .delete, .space,
            .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            nil
        }
    }

    private static func specialKey(
        for scalar: UInt32
    ) -> BrowserShortcutSpecialKey? {
        switch scalar {
        case 0xF700: .upArrow
        case 0xF701: .downArrow
        case 0xF702: .leftArrow
        case 0xF703: .rightArrow
        case 0xF704: .f1
        case 0xF705: .f2
        case 0xF706: .f3
        case 0xF707: .f4
        case 0xF708: .f5
        case 0xF709: .f6
        case 0xF70A: .f7
        case 0xF70B: .f8
        case 0xF70C: .f9
        case 0xF70D: .f10
        case 0xF70E: .f11
        case 0xF70F: .f12
        case 0xF728: .forwardDelete
        case 0xF729: .home
        case 0xF72B: .end
        case 0xF72C: .pageUp
        case 0xF72D: .pageDown
        default: nil
        }
    }
}
