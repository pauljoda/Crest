import WebKit

@MainActor
protocol BrowserExtensionPageProviding:
    BrowserExtensionPageSelectionProviding,
    AnyObject
{
    func extensionWebView(for tabID: TabID, in spaceID: SpaceID) -> WKWebView?

    /// Loads an extension-requested URL into the tab runtime appropriate for
    /// that URL. Extension documents require their context's WebKit
    /// configuration, so a provider that owns page lifecycles may swap the
    /// tab's active web view before loading.
    func loadExtensionURL(
        _ url: URL,
        for tabID: TabID,
        in spaceID: SpaceID,
        session: BrowserSession
    )

    /// The tab's last known reader-mode state. Reading it must never start a
    /// probe, so a tab whose page has not been examined reports `.unavailable`.
    func extensionReaderModeState(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserReaderModeState

    func setExtensionReaderModeActive(
        _ isActive: Bool,
        for tabID: TabID,
        in spaceID: SpaceID
    ) async throws

    /// The placement of the real window presenting the Space, or
    /// `.unavailable` when no window is hosting it.
    func extensionWindowGeometry(
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowGeometry
}

extension BrowserExtensionPageProviding {
    func loadExtensionURL(
        _ url: URL,
        for tabID: TabID,
        in spaceID: SpaceID,
        session: BrowserSession
    ) {
        extensionWebView(for: tabID, in: spaceID)?
            .load(URLRequest(url: url))
    }
}
