import Foundation

@MainActor
struct MobileSavedLocationRestoreAction {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let selectTab: (TabID) -> Void

    @discardableResult
    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = browser.selectedSpace,
            space.id == assignment.spaceID,
            space.profile.id == assignment.profileID,
            !browser.deletingSpaceIDs.contains(space.id),
            let tab = space.tabs.first(where: { $0.id == assignment.tabID }),
            tab.isAwayFromSavedLocation,
            tab.savedSiteURL != nil
        else { return false }

        selectTab(assignment.tabID)
        let pageActions = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            expectedAssignment: assignment
        )
        guard let page = pageActions.activePage,
            let url = browser.restoreTabSavedLocation(
                assignment.tabID,
                in: assignment.spaceID
            )
        else { return false }
        page.load(url)
        return true
    }
}
