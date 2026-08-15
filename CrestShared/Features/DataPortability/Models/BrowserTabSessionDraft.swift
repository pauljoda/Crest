struct BrowserTabSessionDraft: Equatable, Sendable {
    let sourceOrdinal: Int
    let name: String?
    let folders: [BrowserTabSessionFolderDraft]
    let tabs: [BrowserTabSessionTabDraft]
    let selectedTabIndex: Int?
    let symbol: String?
    let accent: SpaceAccent?
    let branding: BrowserSpaceBranding?

    init(
        sourceOrdinal: Int,
        name: String?,
        tabs: [BrowserTabSessionTabDraft],
        selectedTabIndex: Int?,
        folders: [BrowserTabSessionFolderDraft] = [],
        symbol: String? = nil,
        accent: SpaceAccent? = nil,
        branding: BrowserSpaceBranding? = nil
    ) {
        self.sourceOrdinal = sourceOrdinal
        self.name = name
        self.folders = folders
        self.tabs = tabs
        self.selectedTabIndex = selectedTabIndex
        self.symbol = symbol
        self.accent = accent
        self.branding = branding
    }
}
