import Foundation

@MainActor
enum BrowserSidebarUtilityActionPolicy {
    static func downloadItem(
        for action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController,
        itemsForProfile: (UUID) -> [BrowserDownloadItem]
    ) -> BrowserDownloadItem? {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: accessController
            )
        else { return nil }
        let itemID = itemID(for: action)
        return itemsForProfile(space.profile.id).first {
            $0.id == itemID && $0.profileID == assignment.profileID
        }
    }

    private static func itemID(
        for action: BrowserUtilityDownloadAction
    ) -> UUID {
        switch action {
        case .open(let id, _), .retry(let id), .cancel(let id), .clear(let id):
            id
        }
    }
}
