import Foundation

/// What an engine adapter asks the browser to do on its behalf.
///
/// The engine names windows, Spaces and URLs; the composition runs the same
/// store, page and window operations Crest's own UI runs for the same request,
/// so no adapter edits the session. Space selection stays the window's own
/// presentation state, changed the way the Space switcher changes it.
@MainActor
protocol BrowserEngineHostCommands: AnyObject {
    /// The persistent Spaces an engine may keep extension state for: every
    /// one that is neither locked nor being deleted.
    var extensionSpaces: [BrowserSpace] { get }
    func extensionSpace(forProfile profileID: UUID) -> BrowserSpace?

    /// Shows `space` in `window` and opens `url` there as its selected tab.
    @discardableResult
    func openTab(_ url: URL, in space: BrowserSpaceRuntimeAssignment, window: BrowserWindowID) -> Bool
    /// Opens a link another app sent in `space`, as Crest's own external-link
    /// handling does for a link routed to a Space.
    @discardableResult
    func openExternalLink(_ url: URL, in space: BrowserSpaceRuntimeAssignment, window: BrowserWindowID) -> Bool
    func openSettings(in window: BrowserWindowID)
    /// Opens Settings on the Extensions pane for `space`.
    func openExtensionSettings(for space: BrowserSpaceRuntimeAssignment, in window: BrowserWindowID)
    func openGettingStarted(in window: BrowserWindowID)
    func selectSpace(_ spaceID: SpaceID, in window: BrowserWindowID)

    /// Writes `window`'s pending session, window and tab state before quit.
    func flushPendingPersistence(in window: BrowserWindowID) async
    /// Ends private browsing once its window has closed.
    func closePrivateBrowsing()
}
