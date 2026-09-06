import Foundation

@MainActor
struct MobileSavedLocationRestoreAction {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let selectTab: (TabID) -> Void
    var spaceAccess = BrowserSpaceAccessController()

    @discardableResult
    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = browser.selectedSpace,
            space.id == assignment.spaceID,
            space.profile.id == assignment.profileID,
            !browser.deletingSpaceIDs.contains(space.id),
            !spaceAccess.isLocked(space),
            let tab = space.tabs.first(where: { $0.id == assignment.tabID }),
            BrowserSavedLocationRestorePolicy.shouldRestore(
                tab, pendingURL: pages.residentPage(matching: assignment)?.pendingNavigationURL
            ),
            !pages.containsResidentPage(for: tab.id) || pages.containsResidentPage(matching: assignment)
        else { return false }

        let hadResidentPage = pages.containsResidentPage(matching: assignment)
        pages.discardArchivedTabState(matching: assignment)
        guard let url = browser.restoreTabSavedLocation(assignment.tabID, in: assignment.spaceID)
        else { return false }
        selectTab(assignment.tabID)
        let pageActions = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            expectedAssignment: assignment
        )
        guard let page = pageActions.activePage
        else { return false }
        if hadResidentPage && page.pendingNavigationURL != url { page.load(url) }
        return true
    }
}
