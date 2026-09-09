extension BrowserPagePool {
    /// Entering a Space restores resident cards, but does not open its
    /// remembered unloaded tabs on the person's behalf.
    func selectSpace(in browser: BrowserStore) {
        guard let space = browser.selectedSpace, let tab = browser.selectedTab else {
            deactivatePagePresentation()
            return
        }
        if browser.consumeMovedTabActivation() {
            select(session: browser.session)
        } else if requiresStartPageOnEntry(to: space) {
            browser.presentStartPageForSpaceEntry()
            deactivatePagePresentation()
        } else if tab.isStartPage && space.splitGroup(containing: tab.id) == nil {
            deactivatePagePresentation()
        } else {
            select(session: browser.session)
        }
    }

    /// The retained content strip asks the same question as selection, without
    /// creating a tab or starting a navigation while preparing a neighbor.
    func requiresStartPageOnEntry(to space: BrowserSpace) -> Bool {
        space.presentedSplitMembers(for: space.selectedTabID).contains { member in
            member.isWebPage
                && !containsResidentPage(
                    matching: BrowserTabRuntimeAssignment(
                        tabID: member.id, spaceID: space.id, profileID: space.profile.id
                    )
                )
        }
    }

    /// Each Space owns one content surface in the retained strip. A resident
    /// page may be drawn there before activation, but it cannot own focus or
    /// input until selection commits. Locked surfaces never mount live pages.
    func surfacePage(
        for tab: BrowserTab, in space: BrowserSpace,
        accessController: BrowserSpaceAccessController
    ) -> BrowserPage? {
        guard !accessController.isLocked(space),
            space.presentedSplitMembers(for: space.selectedTabID).contains(where: { $0.id == tab.id })
        else { return nil }
        return residentPage(
            matching: BrowserTabRuntimeAssignment(
                tabID: tab.id, spaceID: space.id, profileID: space.profile.id))
    }
}
