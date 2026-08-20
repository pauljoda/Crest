import Foundation

/// The archive, history, and downloads actions the sidebar's utility surfaces
/// perform, behind the one access guard they all share.
///
/// Every action re-reads the session at call time and refuses unless the Space
/// the caller named is still the selected, unlocked one it owns — the surfaces
/// hand out captured closures, and a Space can be reselected, relocked, deleted,
/// or have its profile replaced between the capture and the tap. Only the last
/// step of each action differs between the shells; that step comes from
/// `BrowserSidebarUtilityPlatformActions`.
@MainActor
struct BrowserSidebarUtilityCoordinator {
    let browser: BrowserStore
    let downloadCenter: BrowserDownloadCenter
    let spaceAccess: BrowserSpaceAccessController
    let platformActions: BrowserSidebarUtilityPlatformActions

    var selectedDownloads: [BrowserDownloadItem] {
        guard let selectedSpace = browser.selectedSpace,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: selectedSpace),
                in: browser,
                accessController: spaceAccess
            )
        else { return [] }
        return downloadCenter.items(for: space.profile.id)
    }

    var actions: BrowserUtilityListActions {
        BrowserUtilityListActions(
            restoreArchivedTab: restoreArchivedTab,
            openHistoryEntry: openHistoryEntry,
            downloadDestinations: platformActions.downloadDestinations,
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
        downloadCenter.acknowledgeItems(for: space.profile.id)
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
        platformActions.selectRestoredTab(tabID)
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
        platformActions.openHistoryEntry(entry.url, assignment)
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
            platformActions.openFinishedDownload(item, destination)
        case .retry(let itemID):
            Task {
                // The ownership the guard above proved is a moment old by the
                // time this runs, and the retry itself keeps checking as it
                // goes, because a download outlives the tap that asked for it.
                guard downloadItem(for: action, matching: assignment) != nil else {
                    return
                }
                await downloadCenter.retryAutomaticDownload(
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
            platformActions.cancelDownload(itemID)
        case .clear(let itemID):
            platformActions.clearDownload(itemID)
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
            itemsForProfile: downloadCenter.items(for:)
        )
    }
}
