extension BrowserPagePool {
    func activePage(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> BrowserPage? {
        guard activeTabID == assignment.tabID,
            let page = activePage,
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return nil }
        return page
    }

    /// The page of a presented card, once its Space and profile are confirmed
    /// to be the ones the caller is drawing.
    ///
    /// A split card binds a page it did not select, so the drift `activePage(matching:)`
    /// guards against is a live risk here too: a Space switch or a profile
    /// rebuild can leave a card holding a stale assignment for one frame, and
    /// binding a page across that boundary is exactly the isolation failure
    /// per-Space browsing exists to prevent.
    func presentedPage(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> BrowserPage? {
        guard let page = presentedPage(for: assignment.tabID),
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return nil }
        return page
    }
}
