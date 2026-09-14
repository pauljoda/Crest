import Foundation

enum BrowserTabMigrationSanitizer {
    static func title(
        _ source: String,
        fallback: String,
        maximumLength: Int = 4_096
    ) throws -> String {
        let value = BrowserImportValueSanitizer.title(source, fallback: fallback)
        guard !value.isEmpty, value.count <= maximumLength else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }
        return value
    }
}
