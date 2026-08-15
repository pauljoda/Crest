import Foundation

enum BrowserBookmarkValueSanitizer {
    static func title(
        _ source: String,
        fallback: String,
        maximumLength: Int
    ) throws -> String {
        let normalized = collapseWhitespace(source)
        let result = normalized.isEmpty ? collapseWhitespace(fallback) : normalized
        guard !result.isEmpty, result.count <= maximumLength else {
            throw BrowserBookmarkMigrationError.resourceLimitExceeded
        }
        return result
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

    static func date(
        _ value: Any?,
        epoch: BrowserBookmarkDateEpoch,
        fallback: Date
    ) -> Date {
        if let date = value as? Date,
            date.timeIntervalSinceReferenceDate.isFinite
        {
            return date
        }
        let raw: Double?
        if let number = value as? NSNumber {
            raw = number.doubleValue
        } else if let string = value as? String {
            raw = Double(string)
        } else {
            raw = nil
        }
        guard let raw, raw.isFinite, raw > 0 else { return fallback }

        let seconds: Double
        switch epoch {
        case .unixSeconds:
            seconds = raw
        case .unixMicroseconds:
            seconds = raw / 1_000_000
        case .windowsMicroseconds:
            seconds = raw / 1_000_000 - 11_644_473_600
        case .adaptive:
            if raw > 10_000_000_000_000_000 {
                seconds = raw / 1_000_000 - 11_644_473_600
            } else if raw > 10_000_000_000_000 {
                seconds = raw / 1_000_000
            } else if raw > 10_000_000_000 {
                seconds = raw / 1_000
            } else {
                seconds = raw
            }
        }
        guard seconds.isFinite else { return fallback }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
