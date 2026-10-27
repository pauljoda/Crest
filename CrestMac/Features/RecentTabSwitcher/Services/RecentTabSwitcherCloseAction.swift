import Foundation

/// Closes the highlighted item's focused tab without selecting it first or
/// closing the window. A split keeps its other pages; the core decides how
/// current, saved and pinned tabs close after their pages agree to go.
@MainActor
struct RecentTabSwitcherCloseAction {
    // MARK: - Variables

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    // MARK: - Actions - Closing

    /// False includes a deferred decision, which must receive input instead
    /// of the switcher. The captured Space is checked again after approval.
    func perform(_ item: RecentTabItem, in space: BrowserSpaceRuntimeAssignment) -> Bool {
        guard browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess) != nil,
            browser.recentTabItems().contains(item)
        else { return false }
        let assignment = BrowserTabRuntimeAssignment(
            tabID: item.focusedTabID, spaceID: space.spaceID, profileID: space.profileID)
        return browser.performPageDismissal(of: [assignment]) {
            guard browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess) != nil else {
                return false
            }
            return browser.closeSessionTab(assignment.tabID, in: assignment.spaceID)
        }
    }
}
