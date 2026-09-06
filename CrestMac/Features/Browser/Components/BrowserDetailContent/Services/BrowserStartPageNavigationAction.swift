import Foundation

@MainActor
struct BrowserStartPageNavigationAction {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController

    func perform(_ source: BrowserTabRuntimeAssignment, url: URL) -> Bool {
        guard
            BrowserCommandPaletteActionPolicy.isSourceAvailable(
                source,
                in: browser,
                accessController: spaceAccess
            ), browser.selectedTab?.isStartPage == true
        else { return false }
        browser.navigateSelectedTab(to: url)
        // A cold launch or unloaded Space has no active page to receive load().
        // Selecting materializes the draft's page and starts its initial URL.
        pages.select(session: browser.session)
        return true
    }
}
