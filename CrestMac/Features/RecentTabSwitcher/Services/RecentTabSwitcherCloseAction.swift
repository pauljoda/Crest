import Foundation

/// Closes the highlighted tab immediately after its page permits dismissal.
/// Splits keep their other tabs, and the core preserves saved and pinned tabs.
@MainActor
struct RecentTabSwitcherCloseAction {
    // MARK: - Variables

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    // MARK: - Actions - Closing

    /// A false return can mean a deferred decision. Completion reports the
    /// final result, with the originating Space checked again after approval.
    func perform(
        _ item: RecentTabItem, in space: BrowserSpaceRuntimeAssignment, clearsSelection: Bool = false,
        completion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> Bool {
        guard browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess) != nil
        else {
            completion(false)
            return false
        }
        guard browser.recentTabItems().contains(item) else {
            completion(false)
            return false
        }
        let assignment = BrowserTabRuntimeAssignment(
            tabID: item.focusedTabID, spaceID: space.spaceID, profileID: space.profileID)
        return browser.performPageDismissal(of: [assignment], completion: completion) {
            guard browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess) != nil else {
                return false
            }
            // A sole Start Page stays in the core, but this window can
            // leave it unselected instead of closing the window itself.
            let keepsStartPage =
                clearsSelection
                && browser.closingLeavesOnlyTheWindow(assignment.tabID, in: assignment.spaceID)
            guard keepsStartPage || browser.closeSessionTab(assignment.tabID, in: assignment.spaceID) else {
                return false
            }
            if clearsSelection { browser.clearPresentedTabSelection(in: space.spaceID) }
            return true
        }
    }
}
