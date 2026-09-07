extension BrowserPagePool {
    /// Entering a Space restores resident cards, but does not open its
    /// remembered unloaded tabs on the person's behalf.
    func selectSpace(in browser: BrowserStore) {
        guard let space = browser.selectedSpace, let tab = browser.selectedTab else {
            deactivatePagePresentation()
            return
        }
        let members = space.presentedSplitMembers(for: tab.id)
        let requiresLoading = members.contains { member in
            member.isWebPage
                && !containsResidentPage(
                    matching: BrowserTabRuntimeAssignment(
                        tabID: member.id, spaceID: space.id, profileID: space.profile.id
                    )
                )
        }
        if requiresLoading {
            browser.presentStartPageForSpaceEntry()
            deactivatePagePresentation()
        } else if tab.isStartPage && space.splitGroup(containing: tab.id) == nil {
            deactivatePagePresentation()
        } else {
            select(session: browser.session)
        }
    }
}
