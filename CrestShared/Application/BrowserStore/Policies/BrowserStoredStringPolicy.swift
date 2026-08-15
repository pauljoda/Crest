import Foundation

enum BrowserStoredStringPolicy {
    static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
