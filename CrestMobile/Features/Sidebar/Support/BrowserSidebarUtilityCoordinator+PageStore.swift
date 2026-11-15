import Foundation

extension BrowserSidebarUtilityCoordinator {
    /// Binds the sidebar's utility surfaces to the compact shell's page store.
    ///
    /// The compact shell has one page and a navigation stack around it, so a
    /// history entry is routed rather than opened in place and a restored tab
    /// goes through the shell's own selection. Finished files open in Quick
    /// Look, show in the Files app, or leave through the share sheet or the
    /// Files picker.
    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController,
        selectTab: @escaping (UUID) -> Void,
        openURL: @escaping (URL) -> Void
    ) {
        self.init(
            browser: browser,
            downloadCenter: pages.downloadCenter,
            spaceAccess: spaceAccess,
            platformActions: BrowserSidebarUtilityPlatformActions(
                downloadDestinations: MobileBrowserFilePresenter.downloadDestinations,
                openHistoryEntry: { url, _ in openURL(url) },
                selectRestoredTab: selectTab,
                openFinishedDownload: { item, destination in
                    pages.openDownload(item.id, in: destination)
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
