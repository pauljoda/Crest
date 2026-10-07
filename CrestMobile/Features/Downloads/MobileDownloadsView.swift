import SwiftUI

struct MobileDownloadsView: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let assignment: BrowserSpaceRuntimeAssignment
    let spaceAccess: BrowserSpaceAccessController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MobileDownloadsContent(
            space: space,
            downloads: downloads,
            actions: actions,
            dismiss: dismiss.callAsFunction
        )
    }

    private var downloads: [DownloadState] {
        guard let space else { return [] }
        return pages.downloadCenter.items(for: space.profileID)
    }

    private var actions: BrowserUtilityListActions {
        BrowserUtilityListActions(
            downloadDestinations: [.share, .files],
            performDownloadAction: performDownloadAction
        )
    }

    private func performDownloadAction(
        _ action: BrowserUtilityDownloadAction,
        matching rowAssignment: BrowserSpaceRuntimeAssignment
    ) {
        guard rowAssignment == assignment,
            downloadItem(for: action) != nil
        else { return }
        switch action {
        case .open(let itemID, let destination):
            if let export = MobileBrowserFileExportDestination.exporting(destination) {
                pages.exportDownload(itemID, to: export)
            }
        case .retry(let itemID):
            pages.downloadCenter.retryAutomaticDownload(itemID, matching: assignment) { expectedAssignment in
                BrowserSidebarAccessPolicy.unlockedSpace(
                    matching: expectedAssignment,
                    in: browser,
                    accessController: spaceAccess
                ) != nil
            }
        case .cancel(let itemID):
            pages.cancelDownload(itemID)
        case .pause(let itemID):
            pages.downloadCenter.pause(itemID)
        case .resume(let itemID):
            pages.downloadCenter.resume(itemID)
        case .clear(let itemID):
            pages.clearDownload(itemID)
        }
    }

    private func downloadItem(
        for action: BrowserUtilityDownloadAction
    ) -> DownloadState? {
        BrowserSidebarUtilityActionPolicy.downloadItem(
            for: action,
            matching: assignment,
            in: browser,
            accessController: spaceAccess,
            itemsForProfile: pages.downloadCenter.items(for:)
        )
    }

    private var space: SpaceModel? {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        )
    }
}
