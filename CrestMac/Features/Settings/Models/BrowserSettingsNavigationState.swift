import Foundation

struct BrowserSettingsNavigationState: Equatable {
    var selection: BrowserSettingsDestination
    var searchText: String

    init(
        selection: BrowserSettingsDestination = .general,
        searchText: String = ""
    ) {
        self.selection = selection
        self.searchText = searchText
    }

    func visibleDestinations(locale: Locale) -> [BrowserSettingsDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return BrowserSettingsDestination.platformCases
        }

        let matches = BrowserSettingsDestination.platformCases.filter {
            $0.matchesSearchQuery(query, locale: locale)
        }
        guard selection == .passwords, !matches.contains(.passwords) else {
            return matches
        }
        return [.passwords] + matches
    }

    mutating func applyExternalRoute(
        _ destination: BrowserSettingsDestination,
        revision: Int
    ) {
        guard revision > 0 else { return }
        selection = destination
    }
}
