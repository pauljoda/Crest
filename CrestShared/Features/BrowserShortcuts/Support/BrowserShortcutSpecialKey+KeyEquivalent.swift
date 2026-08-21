import SwiftUI

extension BrowserShortcutSpecialKey {
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .tab: return .tab
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .escape: return .escape
        case .returnKey: return .return
        case .delete: return .delete
        case .forwardDelete: return .deleteForward
        case .home: return .home
        case .end: return .end
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .space: return .space
        case .f1, .f2, .f3, .f4, .f5,
            .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15,
            .f16, .f17, .f18, .f19, .f20:
            guard
                let functionKeyNumber,
                let scalar = UnicodeScalar(
                    Self.firstFunctionKeyScalarValue + functionKeyNumber
                )
            else {
                return .escape
            }
            return KeyEquivalent(Character(scalar))
        }
    }

    private static let firstFunctionKeyScalarValue = 0xF703

    private var functionKeyNumber: Int? {
        switch self {
        case .f1: 1
        case .f2: 2
        case .f3: 3
        case .f4: 4
        case .f5: 5
        case .f6: 6
        case .f7: 7
        case .f8: 8
        case .f9: 9
        case .f10: 10
        case .f11: 11
        case .f12: 12
        case .f13: 13
        case .f14: 14
        case .f15: 15
        case .f16: 16
        case .f17: 17
        case .f18: 18
        case .f19: 19
        case .f20: 20
        case .tab, .leftArrow, .rightArrow, .upArrow, .downArrow,
            .escape, .returnKey, .delete, .forwardDelete,
            .home, .end, .pageUp, .pageDown, .space:
            nil
        }
    }
}
