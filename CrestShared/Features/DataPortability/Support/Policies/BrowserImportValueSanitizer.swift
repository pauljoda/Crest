import Foundation

enum BrowserImportValueSanitizer {
    static func url(_ source: String, removesFragment: Bool = false) -> URL? {
        guard source.count <= ArchiveLimits.maximumURLLength,
            let candidate = URL(string: source),
            var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false
        else { return nil }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        if removesFragment {
            components.fragment = nil
        }
        return components.url
    }

    static func collapsedWhitespace(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func title(_ source: String, fallback: String) -> String {
        let normalized = collapsedWhitespace(source)
        return normalized.isEmpty ? collapsedWhitespace(fallback) : normalized
    }
}
