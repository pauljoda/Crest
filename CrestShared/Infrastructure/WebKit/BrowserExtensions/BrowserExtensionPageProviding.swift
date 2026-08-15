import WebKit

@MainActor
protocol BrowserExtensionPageProviding:
    BrowserExtensionPageSelectionProviding,
    AnyObject
{
    func extensionWebView(for tabID: TabID, in spaceID: SpaceID) -> WKWebView?

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
