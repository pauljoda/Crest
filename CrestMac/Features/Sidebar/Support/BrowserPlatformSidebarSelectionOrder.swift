@MainActor
enum BrowserPlatformSidebarSelectionOrder {
    static func orderedItems(
        in browser: BrowserStore,
        assignment: BrowserSpaceRuntimeAssignment
    ) -> [BrowserSelectionItemID]? {
        guard browser.selectedSpaceID == assignment.spaceID,
            let space = browser.space(matching: assignment)
        else { return [] }
        let interaction = browser.interactionObserver as? BrowserSidebarInteractionState
        if space.accessPolicy.requiresAuthentication {
            guard let access = interaction?.sidebarSpaceAccess, !access.isLocked(space) else { return [] }
        }
        return BrowserSidebarSelection.logicalItems(in: space) { folderID in
            interaction?.collapsedFolderVisibility(
                for: BrowserFolderRuntimeAssignment(
                    folderID: folderID, spaceID: assignment.spaceID, profileID: assignment.profileID)
            ).state.keptTabID
        }
    }
}
