import Foundation

/// Closes the highlighted tab of a held recent tabs switcher once its page
/// lets it go. A split keeps its other tabs, and a saved or pinned tab keeps
/// its place and puts its page away, as closing it anywhere does.
@MainActor
struct RecentTabSwitcherCloseAction {
    // MARK: - Variables

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    // MARK: - Actions - Closing

    /// Closes `item`'s focused tab in the Space it lives in, which may be
    /// another Space of the held Space's group, or, when `clearsSelection`
    /// and the tab is that Space's last Start Page, shows no tab instead of
    /// closing the window. `completion` tells whether it closed, once the
    /// page answered, which a page asking the person makes later; the held
    /// Space `space` is checked again after the answer.
    func perform(
        _ item: RecentTabItem, in space: BrowserSpaceRuntimeAssignment, clearsSelection: Bool,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess) != nil,
            browser.recentTabItems().contains(item), let home = browser.spaceModel(item.spaceID)
        else {
            completion(false)
            return
        }
        let assignment = BrowserTabRuntimeAssignment(
            tabID: item.focusedTabID, spaceID: home.id, profileID: home.profileID)
        browser.performPageDismissal(of: [assignment], completion: completion) {
            guard browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess) != nil else {
                return false
            }
            // Only the sole Start Page needs special handling. A normal close
            // lets the core select a fallback, even outside the five previews.
            if clearsSelection && browser.closingLeavesOnlyTheWindow(assignment.tabID, in: assignment.spaceID) {
                if browser.selectedTabID(in: assignment.spaceID) == assignment.tabID {
                    browser.clearPresentedTabSelection(in: assignment.spaceID)
                }
                return true
            }
            return browser.closeSessionTab(assignment.tabID, in: assignment.spaceID)
        }
    }
}
