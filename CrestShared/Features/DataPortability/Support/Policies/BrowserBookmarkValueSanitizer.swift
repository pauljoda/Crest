import Foundation

enum BrowserBookmarkValueSanitizer {
    static func title(
        _ source: String,
        fallback: String,
        maximumLength: Int
    ) throws -> String {
        let result = BrowserImportValueSanitizer.title(source, fallback: fallback)
        guard !result.isEmpty, result.count <= maximumLength else {
            throw BrowserBookmarkMigrationError.resourceLimitExceeded
        }
        return result
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
}
