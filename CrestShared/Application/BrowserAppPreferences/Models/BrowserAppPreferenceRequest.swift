import Foundation

/// One `preferences.*` session command as it crosses the core boundary.
struct BrowserAppPreferenceRequest: Encodable, Sendable {
    // MARK: - Types

    /// A preference's new value: a flag, or a term such as a startup behavior.
    enum Value: Encodable, Sendable {
        case flag(Bool)
        case term(String)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .flag(let value): try container.encode(value)
            case .term(let value): try container.encode(value)
            }
        }
    }

    /// Arguments shared by the commands; each command sets its own fields.
    struct Arguments: Encodable, Sendable {
        var preference: BrowserAppPreference?
        var value: Value?
        var sourceID: String?
        var targetID: String?
        var isEnabled: Bool?
        var legacy: BrowserLegacyAppPreferences?
    }

    // MARK: - Variables

    let version = 1
    let operation: BrowserAppPreferenceCommand
    let arguments: Arguments

    // MARK: - Actions - Commands

    static func set(_ preference: BrowserAppPreference, to value: Value) -> BrowserAppPreferenceRequest {
        BrowserAppPreferenceRequest(operation: .set, arguments: Arguments(preference: preference, value: value))
    }

    static func translationRule(sourceID: String, targetID: String, isEnabled: Bool) -> BrowserAppPreferenceRequest {
        BrowserAppPreferenceRequest(
            operation: .translationRule,
            arguments: Arguments(sourceID: sourceID, targetID: targetID, isEnabled: isEnabled))
    }

    static func importing(_ legacy: BrowserLegacyAppPreferences) -> BrowserAppPreferenceRequest {
        BrowserAppPreferenceRequest(operation: .importLegacy, arguments: Arguments(legacy: legacy))
    }
}
