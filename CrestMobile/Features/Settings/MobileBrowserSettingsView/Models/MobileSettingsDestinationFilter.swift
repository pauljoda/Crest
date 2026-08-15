import Foundation

enum MobileSettingsDestinationFilter {
    static func destinations(
        matching searchText: String,
        locale: Locale
    ) -> [BrowserSettingsDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return BrowserSettingsDestination.platformCases
        }
        return BrowserSettingsDestination.platformCases.filter {
            $0.matchesSearchQuery(query, locale: locale)
        }
    }
}
