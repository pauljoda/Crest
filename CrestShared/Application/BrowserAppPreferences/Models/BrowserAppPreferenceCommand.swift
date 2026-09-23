import Foundation

/// The core's `preferences.*` session commands.
enum BrowserAppPreferenceCommand: String, Codable, Sendable {
    case set = "preferences.set"
    case importLegacy = "preferences.import"
    case translationRule = "preferences.translation_rule"
}
