import Foundation

extension BrowserShortcutModifiers {
    var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    func spokenDescription(locale: Locale = .current) -> String {
        let resources: [LocalizedStringResource] = [
            contains(.control) ? "control" : nil,
            contains(.option) ? "option" : nil,
            contains(.shift) ? "shift" : nil,
            contains(.command) ? "command" : nil,
        ].compactMap { $0 }
        return resources.map { resource in
            BrowserShortcutLocalization.string(resource, locale: locale)
        }.joined(separator: " ")
    }

    var spokenDescription: String {
        spokenDescription()
    }
}
