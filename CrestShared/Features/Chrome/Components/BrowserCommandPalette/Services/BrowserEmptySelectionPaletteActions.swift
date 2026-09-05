import Foundation

/// Actions from a window's New Tab surface, before it has a source tab.
/// Each action revalidates the captured Space and the empty selection.
@MainActor
struct BrowserEmptySelectionPaletteActions {
    let source: BrowserSpaceRuntimeAssignment
    let browser: BrowserStore
    let accessController: BrowserSpaceAccessController
    let didSelectTab: () -> Void

    var isAvailable: Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: source,
                in: browser,
                accessController: accessController
            )
        else { return false }
        return space.selectedTabID == nil
    }

    func selectTab(_ target: BrowserTabRuntimeAssignment) -> Bool {
        guard isAvailable,
            target.spaceID == source.spaceID,
            target.profileID == source.profileID,
            browser.selectedSpace?.contains(target.tabID) == true
        else { return false }
        browser.selectTab(target.tabID)
        didSelectTab()
        return true
    }

    func openURL(_ url: URL) -> Bool {
        guard isAvailable,
            browser.openNewTab(url: url, matching: source) != nil
        else { return false }
        didSelectTab()
        return true
    }
}
