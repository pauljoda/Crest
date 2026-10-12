import Foundation

@MainActor
enum BrowserSidebarUtilityActionPolicy {
    static func downloadItem(
        for action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController,
        itemsForProfile: (UUID) -> [DownloadState]
    ) -> DownloadState? {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: accessController
            )
        else { return nil }
        return itemsForProfile(space.profileID).first {
            $0.id == action.itemID && $0.profileID == assignment.profileID
        }
    }
}
