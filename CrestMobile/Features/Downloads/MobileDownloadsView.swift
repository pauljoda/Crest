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

    private var downloads: [BrowserDownloadItem] {
        guard let space else { return [] }
        return pages.downloadCenter.items(for: space.profile.id)
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
            switch destination {
            case .share:
                pages.exportDownload(itemID, to: .share)
            case .files:
                pages.exportDownload(itemID, to: .files)
            case .revealInFinder:
                break
            }
        case .retry(let itemID):
            Task {
                guard downloadItem(for: action) != nil else { return }
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
        for action: BrowserUtilityDownloadAction
    ) -> BrowserDownloadItem? {
        BrowserSidebarUtilityActionPolicy.downloadItem(
            for: action,
            matching: assignment,
            in: browser,
            accessController: spaceAccess,
            itemsForProfile: pages.downloadCenter.items(for:)
        )
    }

    private var space: BrowserSpace? {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        )
    }
}

#Preview("Mobile Downloads") {
    let fixture = MobileBrowserPreviewFixture()

    MobileDownloadsView(
        browser: fixture.browser,
        pages: fixture.pages,
        assignment: BrowserSpaceRuntimeAssignment(space: fixture.space),
        spaceAccess: fixture.spaceAccess
    )
}
