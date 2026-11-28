import Foundation

struct BrowserSettingsNavigationState: Equatable {
    var selection: BrowserSettingsSidebarItem
    var searchText: String

    init(
        selection: BrowserSettingsSidebarItem = .destination(.general),
        searchText: String = ""
    ) {
        self.selection = selection
        self.searchText = searchText
    }

    /// The destination the selection shows, or nil for a Space's page.
    var destination: BrowserSettingsDestination? {
        if case .destination(let destination) = selection { destination } else { nil }
    }

    var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the sidebar lists the sections a search matches under their
    /// pages: once the search is two characters or more, so a single letter
    /// doesn't list every section of every page.
    var listsSections: Bool {
        query.count >= 2
    }

    /// The destinations the sidebar lists: those `state`'s engines provide,
    /// matching the search. A match inside a page that lives under another
    /// lists the page it lives under.
    @MainActor
    func visibleDestinations(locale: Locale, in state: CoreState) -> [BrowserSettingsDestination] {
        BrowserSettingsDestination.visible(
            matching: searchText, locale: locale, in: state,
            parent: BrowserPlatformSettingsDestinationCatalog.parent(of:))
    }

    /// The page of every Space whose words the search matches, if any.
    @MainActor
    func matchingSpaceTab(locale: Locale, in state: CoreState) -> BrowserSpaceSettingsTab? {
        guard !query.isEmpty else { return nil }
        return BrowserSpaceSettingsTab.matching(query, locale: locale, in: state)
    }

    /// Whether the sidebar lists `space`: no search, a search for its name,
    /// or one for words on its pages (`spaceTab`).
    @MainActor
    func lists(_ space: SpaceModel, spaceTab: BrowserSpaceSettingsTab?) -> Bool {
        query.isEmpty || spaceTab != nil || space.settings.name.localizedStandardContains(query)
    }
}
