import Foundation

extension BrowserSettingsDestination {
    /// The destination's own title and subtitle in `locale`, for filtering
    /// only. Presentation remains deferred through ``LocalizedStringResource``.
    private func pageSearchIndex(locale: Locale) -> String {
        [title, navigationTitle, subtitle]
            .map { resource in
                var localizedResource = resource
                localizedResource.locale = locale
                return String(localized: localizedResource)
            }
            .joined(separator: " ")
    }

    /// Whether the query finds the page: its title or subtitle, or a section
    /// the device offers on it.
    @MainActor
    func matchesSearchQuery(_ query: String, locale: Locale, in state: CoreState) -> Bool {
        pageSearchIndex(locale: locale).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        ) != nil || firstSection(matching: query, locale: locale, in: state) != nil
    }

    /// The first section on the page, in drawing order, whose words the query
    /// finds, where a search result opens the page.
    @MainActor
    func firstSection(matching query: String, locale: Locale, in state: CoreState) -> BrowserSettingsSection? {
        sections.first { $0.isProvided(in: state) && $0.matchesSearchQuery(query, locale: locale) }
    }

    /// Every section on the page, in drawing order, whose words the query
    /// finds, which a search lists under the page.
    @MainActor
    func sections(matching query: String, locale: Locale, in state: CoreState) -> [BrowserSettingsSection] {
        sections.filter { $0.isProvided(in: state) && $0.matchesSearchQuery(query, locale: locale) }
    }
}

extension BrowserSettingsDestination {
    /// Every settings page as the command palette offers it: by its name,
    /// with its title and the words a person might type to find it, which are
    /// those of the sections this platform draws on it while `state`'s engines
    /// provide them, as Settings search finds them.
    @MainActor
    static func palettePages(in state: CoreState) -> [PaletteSettingsPage] {
        all.map { destination in
            PaletteSettingsPage(
                name: destination.name, title: String(localized: destination.title),
                terms: ([String(localized: destination.subtitle)]
                    + destination.sections
                    .filter { $0.isProvided(in: state) }
                    .map { $0.searchIndex(locale: .current) })
                    .joined(separator: " "))
        }
    }
}
