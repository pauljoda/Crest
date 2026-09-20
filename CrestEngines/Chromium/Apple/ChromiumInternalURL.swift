import Foundation

/// Crest's address namespace is separate from Chromium's privileged origins.
/// Translate only at the engine boundary, leaving web and extension URLs intact.
enum ChromiumInternalURL {
    static func engine(_ value: String) -> String {
        replacingScheme(in: value, from: "crest", to: "chrome")
    }

    static func presented(_ value: String) -> String {
        replacingScheme(in: value, from: "chrome", to: "crest")
    }

    static func presentedValues(_ values: [String: Any]) -> [String: Any] {
        guard let url = values["url"] as? String else { return values }
        var result = values
        result["url"] = presented(url)
        return result
    }

    private static func replacingScheme(in value: String, from: String, to: String) -> String {
        let prefix = from + "://"
        guard value.prefix(prefix.count).lowercased() == prefix else { return value }
        // Preserve escaped paths, query strings and fragments byte for byte.
        return to + "://" + value.dropFirst(prefix.count)
    }
}
