import Foundation

@MainActor
struct BrowserDurableTabCloseAction {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var preferences: BrowserDurableTabPreferenceStore = .shared
    /// Retires only the matching page. False means another runtime owns it.
    let closePage: (BrowserTabRuntimeAssignment, Bool) -> Bool

    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID),
                in: browser, accessController: spaceAccess
            ), let tab = space.tabs.first(where: { $0.id == assignment.tabID }),
            tab.placement != .current
        else { return false }
        let returnsToRoot = preferences.closePolicy == .returnToSavedURL && tab.savedSiteURL != nil
        guard closePage(assignment, returnsToRoot) else { return false }
        return browser.closeDurableTab(assignment, returningToSavedURL: returnsToRoot)
    }
}
