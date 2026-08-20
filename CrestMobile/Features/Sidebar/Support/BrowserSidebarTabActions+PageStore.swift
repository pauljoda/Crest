import Foundation

extension BrowserSidebarTabActions {
    /// Binds a Space's sidebar row actions to the compact shell's page store.
    ///
    /// The compact shell keeps one page and follows the session's selection on
    /// its own, so a tab-list mutation leaves it nothing to reconcile.
    init(
        assignment: BrowserSpaceRuntimeAssignment,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.init(
            assignment: assignment,
            browser: browser,
            spaceAccess: spaceAccess,
            syncPagesAfterMutation: {},
            pullFavicon: { tabID, assignment in
                await pages.pullFavicon(for: tabID, matching: assignment)
            }
        )
    }
}
