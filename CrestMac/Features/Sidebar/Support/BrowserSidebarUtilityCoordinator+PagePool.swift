import AppKit

extension BrowserSidebarUtilityCoordinator {
    /// Binds the sidebar's utility surfaces to the window's card pool.
    ///
    /// The windowed shell answers every utility action in place: history opens
    /// a tab in the Space the reader is looking at, a restored tab takes the
    /// selection, and a finished file goes to Finder. The pool is captured
    /// rather than read once, so each closure works against the session as it
    /// stands when the reader taps.
    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.init(
            browser: browser,
            downloadCenter: pages.downloadCenter,
            spaceAccess: spaceAccess,
            platformActions: BrowserSidebarUtilityPlatformActions(
                downloadDestinations: [.open, .revealInFinder],
                openHistoryEntry: { url, assignment in
                    guard browser.openNewTab(url: url, matching: assignment) != nil
                    else { return }
                    pages.select(session: browser.session)
                    pages.load(url)
                },
                selectRestoredTab: { tabID in
                    browser.selectTab(tabID)
                    pages.select(session: browser.session)
                },
                openFinishedDownload: { item, destination in
                    guard item.state == .finished,
                        let destinationURL = item.destinationURL
                    else { return }
                    switch destination {
                    case .open:
                        NSWorkspace.shared.open(destinationURL)
                    case .revealInFinder:
                        NSWorkspace.shared.activateFileViewerSelecting([
                            destinationURL
                        ])
                    case .share, .files:
                        break
                    }
                },
                cancelDownload: { itemID in
                    pages.downloadCenter.cancel(itemID)
                },
                clearDownload: { itemID in
                    pages.downloadCenter.clear(itemID)
                }
            )
        )
    }
}
