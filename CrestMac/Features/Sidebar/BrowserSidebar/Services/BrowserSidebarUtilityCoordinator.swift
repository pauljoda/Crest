import AppKit

@MainActor
struct BrowserSidebarUtilityCoordinator {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController

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
            downloadDestinations: [.open, .revealInFinder],
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
        browser.selectTab(tabID)
        pages.select(session: browser.session)
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
            ) != nil,
            browser.openNewTab(url: entry.url, matching: assignment) != nil
        else { return }
        pages.select(session: browser.session)
        pages.load(entry.url)
    }

    private func performDownloadAction(
        _ action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard let item = downloadItem(for: action, matching: assignment) else {
            return
        }
        switch action {
        case .open(_, let destination):
            openFinishedDownload(item, destination: destination)
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
            pages.downloadCenter.cancel(itemID)
        case .clear(let itemID):
            pages.downloadCenter.clear(itemID)
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

    private func openFinishedDownload(
        _ item: BrowserDownloadItem,
        destination: BrowserUtilityDownloadDestination
    ) {
        guard item.state == .finished,
            let destinationURL = item.destinationURL
        else { return }
        switch destination {
        case .open:
            NSWorkspace.shared.open(destinationURL)
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        case .share, .files:
            break
        }
    }
}
