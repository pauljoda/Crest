import Foundation

@MainActor
struct BrowserDurableTabCloseAction {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var preferences: BrowserAppPreferenceStore = .shared
    /// Retires only the matching page. False means another runtime owns it.
    let closePage: (BrowserTabRuntimeAssignment, Bool) -> Bool

    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID),
                in: browser, accessController: spaceAccess
            ), let tab = space.tabs.first(where: { $0.id == assignment.tabID }),
            tab.placement.isDurable
        else { return false }
        // TRANSITIONAL until WP C slice (g) sequences before-unload in the core:
        // the engine closes the page first, keeping its state only when the
        // core will leave the tab where it is, which the same preference says.
        let returnsToRoot = preferences.savedTabClosePolicy == .returnToSavedURL && tab.savedSiteURL != nil
        return browser.performPageDismissal(of: [assignment]) {
            guard BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID),
                in: browser, accessController: spaceAccess) != nil,
                closePage(assignment, returnsToRoot) else { return false }
            return browser.closeDurableTab(assignment)
        }
    }
}
