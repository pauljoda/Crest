import Foundation

extension BrowserSidebarUtilityCoordinator {
    /// Binds the sidebar's utility surfaces to the compact shell's page store.
    ///
    /// The compact shell has one page and a navigation stack around it, so a
    /// history entry is routed rather than opened in place and a restored tab
    /// goes through the shell's own selection. Finished files leave through the
    /// share sheet or the Files app, which is the store's export path.
    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController,
        selectTab: @escaping (TabID) -> Void,
        openURL: @escaping (URL) -> Void
    ) {
        self.init(
            browser: browser,
            downloadCenter: pages.downloadCenter,
            spaceAccess: spaceAccess,
            platformActions: BrowserSidebarUtilityPlatformActions(
                downloadDestinations: [.share, .files],
                openHistoryEntry: { url, _ in openURL(url) },
                selectRestoredTab: selectTab,
                openFinishedDownload: { item, destination in
                    switch destination {
                    case .share:
                        pages.exportDownload(item.id, to: .share)
                    case .files:
                        pages.exportDownload(item.id, to: .files)
                    case .open, .revealInFinder:
                        break
                    }
                },
                cancelDownload: { itemID in
                    pages.cancelDownload(itemID)
                },
                clearDownload: { itemID in
                    pages.clearDownload(itemID)
                }
            )
        )
    }
}
