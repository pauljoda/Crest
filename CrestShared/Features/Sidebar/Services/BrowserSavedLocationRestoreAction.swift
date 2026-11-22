import Foundation

/// Sends a tab that has wandered back to the location it was saved at.
///
/// It needs the page that is on screen once the tab shows, which each shell
/// finds in its own place: the Mac in the window's card pool, iPhone and iPad
/// through the selected-page port. The shell answers that through `show`.
@MainActor
struct BrowserSavedLocationRestoreAction {
    // MARK: - Variables

    let browser: BrowserStore
    let pages: any BrowserPageOwner
    let spaceAccess: BrowserSpaceAccessController
    /// Shows the tab, and answers the page on screen for it then.
    let show: (BrowserTabRuntimeAssignment) -> BrowserPlatformPage?

    // MARK: - Actions - Restoring

    /// Updates the tab before selection so an unloaded page starts at its root.
    /// A resident page keeps its native history. A tab already home with no
    /// navigation away, or outside the selected unlocked Space, is left alone.
    @discardableResult
    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = browser.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID),
                accessController: spaceAccess),
            let tab = space.shownTab(assignment.tabID),
            browser.returnsToSavedAddress(tab.id, in: space.id),
            !pages.containsResidentPage(for: tab.id) || pages.containsResidentPage(matching: assignment)
        else { return false }
        let hadResidentPage = pages.containsResidentPage(matching: assignment)
        pages.discardArchivedTabState(matching: assignment)
        guard let url = browser.restoreTabSavedLocation(assignment.tabID, in: assignment.spaceID),
            let page = show(assignment)
        else { return false }
        if hadResidentPage && page.live.pendingNavigationURL != url { page.corePage.load(url) }
        return true
    }
}
