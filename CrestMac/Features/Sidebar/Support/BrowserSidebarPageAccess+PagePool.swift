import Foundation

extension BrowserSidebarPageAccess {
    /// Binds the sidebar's page seam to the window's card pool.
    ///
    /// The pool is captured rather than read once: every closure goes back to
    /// it at call time, which is what keeps a row's residency and favicon
    /// reads inside Observation's tracking.
    init(pages: BrowserPagePool, browser: BrowserStore, spaceAccess: BrowserSpaceAccessController) {
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
            selectPages: { pages.selectSpace(in: browser) },
            deactivatePagePresentation: { pages.deactivatePagePresentation() },
            unloadPage: { tabID, assignment in
                guard let tab = browser.space(matching: assignment)?.tabs.first(where: { $0.id == tabID })
                else { return }
                if tab.placement == .current {
                    pages.unloadPage(for: tabID, matching: assignment)
                } else if BrowserDurableTabCloseAction(
                    browser: browser, spaceAccess: spaceAccess,
                    closePage: { pages.closeDurablePage($0, discardState: $1) }
                ).perform(
                    BrowserTabRuntimeAssignment(
                        tabID: tabID, spaceID: assignment.spaceID, profileID: assignment.profileID
                    ))
                {
                    pages.select(session: browser.session)
                }
            },
            pullFavicon: { tabID, assignment in
                await pages.pullFavicon(for: tabID, matching: assignment)
            },
            downloadCenter: pages.downloadCenter
        )
    }
}
