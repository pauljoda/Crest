import Foundation

extension BrowserShortcutKey {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        switch self {
        case .character(let character):
            String(character).uppercased()
        case .special(let key):
            key.displayString(locale: locale)
        }
    }

    func spokenDescription(locale: Locale = .current) -> String {
        switch self {
        case .character(let character):
            String(character).lowercased()
        case .special(let key):
            key.spokenDescription(locale: locale)
        }
    }

    var spokenDescription: String {
        spokenDescription()
    }
}
