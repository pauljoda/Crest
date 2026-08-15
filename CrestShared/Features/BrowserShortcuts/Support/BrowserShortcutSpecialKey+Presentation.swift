import Foundation

extension BrowserShortcutSpecialKey {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        switch self {
        case .tab: "⇥"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .escape: "⎋"
        case .returnKey: "↩"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .space:
            BrowserShortcutLocalization.string("Space", locale: locale)
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        case .f13: "F13"
        case .f14: "F14"
        case .f15: "F15"
        case .f16: "F16"
        case .f17: "F17"
        case .f18: "F18"
        case .f19: "F19"
        case .f20: "F20"
        }
    }

    func spokenDescription(locale: Locale = .current) -> String {
        guard let resource = spokenDescriptionResource else { return rawValue }
        return BrowserShortcutLocalization.string(resource, locale: locale)
    }

    var spokenDescription: String {
        spokenDescription()
    }

    private var spokenDescriptionResource: LocalizedStringResource? {
        switch self {
        case .tab: "tab"
        case .leftArrow: "left arrow"
        case .rightArrow: "right arrow"
        case .upArrow: "up arrow"
        case .downArrow: "down arrow"
        case .escape: "escape"
        case .returnKey: "return"
        case .delete: "delete"
        case .forwardDelete: "forward delete"
        case .home: "home"
        case .end: "end"
        case .pageUp: "page up"
        case .pageDown: "page down"
        case .space: "space"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            nil
        }
    }
}
