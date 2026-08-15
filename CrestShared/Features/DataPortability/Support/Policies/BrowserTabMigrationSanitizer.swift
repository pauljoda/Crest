import Foundation

enum BrowserTabMigrationSanitizer {
    static func title(
        _ source: String,
        fallback: String,
        maximumLength: Int = 4_096
    ) throws -> String {
        let normalized = source.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedFallback = fallback.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let value = normalized.isEmpty ? normalizedFallback : normalized
        guard !value.isEmpty, value.count <= maximumLength else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }
        return value
    }

    static func url(_ source: String) -> URL? {
        guard source.count <= 8_192,
            let candidate = URL(string: source),
            var components = URLComponents(
                url: candidate,
                resolvingAgainstBaseURL: false
            ),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false
        else { return nil }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        return components.url
    }
}
