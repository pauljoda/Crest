/// How the Mac's Settings sidebar groups its destinations.
enum BrowserPlatformSettingsDestinationCatalog {
    /// The sidebar's groups of destinations, in order. Spaces list between
    /// the last two groups. Spaces and Extensions are pages of a Space, and
    /// Feature Flags is a page of Advanced, so none has a row. Autofill has
    /// its own Space picker, and each Space's page opens it on that Space.
    static let groups: [[BrowserSettingsDestination]] = [
        [
            .general, .tabs, .search, .lookAndFeel, .links, .engines, .shortcuts, .sync, .privacy, .adBlocking,
            .passwords,
        ],
        [.agents, .advanced, .about],
    ]

    /// Destinations without a row, each opened from the page of the
    /// destination whose row stands for it.
    static let parents: [BrowserSettingsDestination: BrowserSettingsDestination] = [.featureFlags: .advanced]

    /// The destination whose row stands for `destination` when it has none.
    static func parent(of destination: BrowserSettingsDestination) -> BrowserSettingsDestination? {
        parents[destination]
    }
}
