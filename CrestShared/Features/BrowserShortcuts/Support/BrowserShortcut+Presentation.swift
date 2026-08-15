import Foundation

extension BrowserShortcut {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        modifiers.displayString + key.displayString(locale: locale)
    }

    func spokenDescription(locale: Locale = .current) -> String {
        [
            modifiers.spokenDescription(locale: locale),
            key.spokenDescription(locale: locale),
        ].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var spokenDescription: String {
        spokenDescription()
    }
}
