struct BrowserCommandPaletteInput: Sendable {
    var query: String
    var space: BrowserSpace?
    var selectedTabID: TabID?
    var otherSpaces: [BrowserSpace]
    var commands: [BrowserShortcutCommand]
    var searchProvider: BrowserSearchProvider
    /// Present only while the query addresses a registered omnibox keyword, in
    /// which case that provider's rows replace every other source.
    var omnibox: BrowserCommandPaletteOmniboxContext?

    init(
        query: String,
        space: BrowserSpace?,
        selectedTabID: TabID? = nil,
        otherSpaces: [BrowserSpace] = [],
        commands: [BrowserShortcutCommand] = [],
        searchProvider: BrowserSearchProvider = .google,
        omnibox: BrowserCommandPaletteOmniboxContext? = nil
    ) {
        self.query = query
        self.space = space
        self.selectedTabID = selectedTabID
        self.otherSpaces = otherSpaces
        self.commands = commands
        self.searchProvider = searchProvider
        self.omnibox = omnibox
    }
}
