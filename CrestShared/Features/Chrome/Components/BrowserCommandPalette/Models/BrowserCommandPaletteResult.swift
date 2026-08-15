struct BrowserCommandPaletteResult: Identifiable, Equatable, Sendable {
    let section: BrowserCommandPaletteSection?
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let searchProvider: BrowserSearchProvider?
    let trailing: String
    let target: BrowserCommandPaletteTarget

    init(
        section: BrowserCommandPaletteSection?,
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        searchProvider: BrowserSearchProvider? = nil,
        trailing: String,
        target: BrowserCommandPaletteTarget
    ) {
        self.section = section
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.searchProvider = searchProvider
        self.trailing = trailing
        self.target = target
    }

    var isIntent: Bool { section == nil }

    var faviconTabID: TabID? {
        switch target {
        case .tab(let assignment), .spaceTab(let assignment): assignment.tabID
        case .url, .command, .omniboxSuggestion: nil
        }
    }

    var foreignSpaceID: SpaceID? {
        switch target {
        case .spaceTab(let assignment): assignment.spaceID
        case .tab, .url, .command, .omniboxSuggestion: nil
        }
    }

    /// The provider handoff this row carries, when it came from keyword mode.
    var omniboxAcceptance: BrowserOmniboxAcceptance? {
        guard case .omniboxSuggestion(let acceptance) = target else { return nil }
        return acceptance
    }
}
