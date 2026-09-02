extension BrowserPagePool {
    /// Lets a store observer recognize a selection already performed by the
    /// initiating command. Every card must match, including its runtime and
    /// any first navigation still owed after extension preparation.
    func isPresentingSelection(in session: BrowserSession) -> Bool {
        guard let space = session.selectedSpace,
            let tab = session.selectedTab,
            activeTabID == tab.id
        else { return false }
        let members = space.presentedSplitMembers(for: tab.id)
        guard presentedTabIDs == members.map(\.id) else { return false }
        return members.allSatisfy { member in
            guard
                let page = presentedPage(
                    matching: BrowserTabRuntimeAssignment(
                        tabID: member.id,
                        spaceID: space.id,
                        profileID: space.profile.id
                    )
                )
            else { return false }
            return member.url == nil || page.url != nil
                || page.pendingNavigationURL != nil
                || page.navigationFailure != nil
                || page.isAwaitingPopupNavigation
        }
    }

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
