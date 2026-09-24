import Foundation

extension BrowserSettingsDestination {
    /// The concrete localized haystack used only while filtering Settings.
    /// Presentation remains deferred through ``LocalizedStringResource``.
    private func searchIndex(locale: Locale) -> String {
        [title, navigationTitle, subtitle, searchTerms]
            .map { resource in
                var localizedResource = resource
                localizedResource.locale = locale
                return String(localized: localizedResource)
            }
            .joined(separator: " ")
    }

    func matchesSearchQuery(_ query: String, locale: Locale) -> Bool {
        searchIndex(locale: locale).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        ) != nil
    }
}
