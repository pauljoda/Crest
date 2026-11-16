import Foundation

/// Puts a saved or pinned tab's page away, as closing it does. The core asks
/// the page whether it may go first, then records the close, which returns
/// the tab to its saved address when the app's preferences say so; the page
/// host of the window that asked follows it and lets the page go.
@MainActor
struct BrowserDurableTabCloseAction {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// False when the tab is not a saved or pinned tab of an unlocked Space
    /// this window shows, or its page may not go yet.
    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        perform([assignment])
    }

    /// Puts several saved or pinned tabs' pages away together, asking their
    /// pages once, as a batch of open tabs closes. An engine that answers for
    /// its pages later takes one question at a time, so closing them one by
    /// one would leave all but the first, and a window that showed one of
    /// them returns to a tab outside them. False when any of them is not a
    /// saved or pinned tab of the same unlocked Space this window shows, or
    /// their pages may not go yet.
    func perform(_ assignments: [BrowserTabRuntimeAssignment]) -> Bool {
        guard let first = assignments.first else { return false }
        let space = BrowserSpaceRuntimeAssignment(spaceID: first.spaceID, profileID: first.profileID)
        guard
            let unlocked = browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess),
            assignments.allSatisfy({
                $0.spaceID == space.spaceID && $0.profileID == space.profileID
                    && unlocked.shownTab($0.tabID)?.placement.isDurable == true
            })
        else { return false }
        return browser.performPageDismissal(of: assignments) {
            guard
                browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess) != nil
            else { return false }
            return assignments.count == 1
                ? browser.closeDurableTab(first) : browser.closeDurableTabs(assignments)
        }
    }
}
