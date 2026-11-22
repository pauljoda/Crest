import Foundation

extension BrowserStore {
    /// Records an explicit close without removing the durable tab or archiving
    /// it: the core puts its page away, back at its saved address when the
    /// app's preferences say so. The page owner retires its runtime before
    /// publishing this session change.
    @discardableResult
    func closeDurableTab(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        let spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID, profileID: assignment.profileID
        )
        guard let space = spaceModel(matching: spaceAssignment),
            let tab = space.shownTab(assignment.tabID),
            tab.placement.isDurable
        else { return false }
        // The core returns the window to the tab it showed before, skipping the
        // closed tab's split, whose other members would present it again.
        return closeSessionTab(tab.id, in: space.id)
    }

    /// Closes several saved or pinned tabs of one Space together: the core
    /// puts their pages away, and a window that showed one of them returns to
    /// a tab outside them rather than to another of them.
    @discardableResult
    func closeDurableTabs(_ assignments: [BrowserTabRuntimeAssignment]) -> Bool {
        guard let first = assignments.first,
            let space = spaceModel(
                matching: BrowserSpaceRuntimeAssignment(spaceID: first.spaceID, profileID: first.profileID))
        else { return false }
        let tabIDs = assignments.compactMap { space.shownTab($0.tabID) }.filter(\.placement.isDurable).map(\.id)
        guard !tabIDs.isEmpty else { return false }
        return family.perform(
            PutAwayTabs(workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id, tabIDs: tabIDs),
            from: self) != nil
    }
}
