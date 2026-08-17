import Foundation

@MainActor
struct MobileBrowserSidebarUtilityCoordinator {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectTab: (TabID) -> Void
    let openURL: (URL) -> Void

    var selectedDownloads: [BrowserDownloadItem] {
        guard let selectedSpace = browser.selectedSpace,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: selectedSpace),
                in: browser,
                accessController: spaceAccess
            )
        else { return [] }
        return pages.downloadCenter.items(for: space.profile.id)
    }

    var actions: BrowserUtilityListActions {
        BrowserUtilityListActions(
            restoreArchivedTab: restoreArchivedTab,
            openHistoryEntry: openHistoryEntry,
            downloadDestinations: [.share, .files],
            performDownloadAction: performDownloadAction
        )
    }

    func acknowledgeDownloads(ifPresented surface: BrowserUtilitySurface?) {
        guard surface == .downloads,
            let selectedSpace = browser.selectedSpace,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: selectedSpace),
                in: browser,
                accessController: spaceAccess
            )
        else { return }
        pages.downloadCenter.acknowledgeItems(for: space.profile.id)
    }

    private func restoreArchivedTab(
        _ tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard
            BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            ) != nil,
            browser.restoreArchivedTab(tabID, matching: assignment)
        else { return }
        selectTab(tabID)
    }

    private func openHistoryEntry(
        _ entry: BrowserHistoryEntry,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard
            BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            ) != nil
        else { return }
        openURL(entry.url)
    }

    private func performDownloadAction(
        _ action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard downloadItem(for: action, matching: assignment) != nil else {
            return
        }
        switch action {
        case .open(let itemID, let destination):
            switch destination {
            case .share:
                pages.exportDownload(itemID, to: .share)
            case .files:
                pages.exportDownload(itemID, to: .files)
            case .open, .revealInFinder:
                break
            }
        case .retry(let itemID):
            Task {
                guard downloadItem(for: action, matching: assignment) != nil else {
                    return
                }
                await pages.downloadCenter.retryAutomaticDownload(
                    itemID,
                    matching: assignment
                ) { expectedAssignment in
                    BrowserSidebarAccessPolicy.unlockedSpace(
                        matching: expectedAssignment,
                        in: browser,
                        accessController: spaceAccess
                    ) != nil
                }
            }
        case .cancel(let itemID):
            pages.cancelDownload(itemID)
        case .clear(let itemID):
            pages.clearDownload(itemID)
        }
    }

    private func downloadItem(
        for action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserDownloadItem? {
        BrowserSidebarUtilityActionPolicy.downloadItem(
            for: action,
            matching: assignment,
            in: browser,
            accessController: spaceAccess,
            itemsForProfile: pages.downloadCenter.items(for:)
        )
    }
}
