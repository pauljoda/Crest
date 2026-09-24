import Foundation

// MARK: - Pages

extension BrowserStore {
    /// Opens a page through the core, from this window, for `tabID` in
    /// `spaceID`, or for a transient request when `tabID` is nil. `webKit`
    /// builds the page when WebKit hosts it. Nil when a rule refuses it, such
    /// as a locked Space, one being deleted, or a tab that already has a page.
    func openPage(
        in spaceID: SpaceID, for tabID: TabID?, webKit: @escaping @MainActor (CorePage) -> AnyObject?
    ) -> Engines.OpenedPage? {
        core.engines.open(
            OpenPage(
                pageID: UUID(), workspaceID: window.workspaceID, spaceID: spaceID.rawValue, tabID: tabID?.rawValue,
                windowID: windowID.rawValue),
            webKit: webKit)
    }

    /// Gives `page` to `tabID` in `spaceID` of this window's workspace, or to
    /// a transient request when `tabID` is nil, hosted by this window. False
    /// when a rule refuses it.
    func adoptPage(_ page: CorePage, in spaceID: SpaceID, as tabID: TabID?) -> Bool {
        page.move(to: window.workspaceID, spaceID: spaceID, tabID: tabID, windowID: windowID)
    }

    /// Whether returning `tabID` to its saved address would change anything,
    /// as the core answers it for this window: the tab is away from that
    /// page, or its page here is heading to another.
    func returnsToSavedAddress(_ tabID: TabID, in spaceID: SpaceID) -> Bool {
        let question = CanReturnToSavedAddress(
            workspaceID: window.workspaceID, windowID: windowID.rawValue, spaceID: spaceID.rawValue,
            tabID: tabID.rawValue)
        return (try? core.query(question))?.changesPage ?? false
    }
}
