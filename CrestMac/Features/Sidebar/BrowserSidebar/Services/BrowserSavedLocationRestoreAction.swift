import Foundation

/// Sends a tab that has wandered back to the location it was saved at.
///
/// This is the one sidebar row action the shells cannot share: it needs the
/// page that is on screen right now, and the two shells find that page in
/// different places — this one in the window's card pool, the compact shell
/// through its own selected-page port.
@MainActor
struct BrowserSavedLocationRestoreAction {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController

    /// Selects the tab, then loads its saved URL into the page that selection
    /// brought up. A tab that is already home, has no saved URL, or lives
    /// outside the selected unlocked Space is left alone.
    @discardableResult
    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                ),
                in: browser,
                accessController: spaceAccess
            ),
            let tab = space.tabs.first(where: { $0.id == assignment.tabID }),
            tab.isAwayFromSavedLocation,
            tab.savedSiteURL != nil
        else { return false }
        browser.selectTab(assignment.tabID)
        pages.select(session: browser.session)
        guard let page = pages.activePage(matching: assignment),
            let url = browser.restoreTabSavedLocation(
                assignment.tabID,
                in: assignment.spaceID
            )
        else { return false }
        page.load(url)
        return true
    }
}
