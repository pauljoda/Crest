import Foundation

extension BrowserSidebarPageAccess {
    /// Binds the sidebar's page seam to the compact shell's page store.
    ///
    /// The store is captured rather than read once: every closure goes back to
    /// it at call time, which is what keeps a row's residency and favicon
    /// reads inside Observation's tracking.
    init(pages: MobileBrowserPageStore, browser: BrowserStore) {
        self.init(
            containsResidentPage: { tabID in
                pages.containsResidentPage(for: tabID)
            },
            containsResidentPageMatching: { assignment in
                pages.containsResidentPage(matching: assignment)
            },
            siteThemeIconAccent: { assignment in
                pages.siteThemeIconAccent(matching: assignment)
            },
            residencyRevision: { pages.residencyRevision },
            selectPages: { pages.select(session: browser.session) },
            deactivatePagePresentation: { pages.deactivatePagePresentation() },
            unloadPage: { tabID, assignment in
                pages.unloadPage(for: tabID, matching: assignment)
            },
            pullFavicon: { tabID, assignment in
                await pages.pullFavicon(for: tabID, matching: assignment)
            },
            downloadCenter: pages.downloadCenter
        )
    }
}
