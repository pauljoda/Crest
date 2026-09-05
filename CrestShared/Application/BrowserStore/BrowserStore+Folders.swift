import Foundation

extension BrowserStore {
    var extensionTabGroups: BrowserExtensionTabGroupStore { family.extensionTabGroups }

    @discardableResult
    func createTabFolder(_ tabs: [TabID], in spaceID: SpaceID) -> FolderID? {
        guard !deletingSpaceIDs.contains(spaceID),
            let id = session.createTabFolder(tabs, in: spaceID)
        else { return nil }
        persist(syncUrgency: .coalesced, scope: .core)
        return id
    }

    @discardableResult
    func fileTabs(
        _ tabs: [TabID], matching assignment: BrowserSpaceRuntimeAssignment,
        into folderID: FolderID?, location: BrowserFolderLocation, before anchor: TabID? = nil,
        beforeFolderID: FolderID? = nil
    ) -> Bool {
        guard space(matching: assignment) != nil,
            session.fileTabs(
                tabs, in: assignment.spaceID, into: folderID, location: location, before: anchor,
                beforeFolderID: beforeFolderID)
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func moveFolder(
        _ id: FolderID, matching assignment: BrowserSpaceRuntimeAssignment,
        to location: BrowserFolderLocation, into parentID: FolderID? = nil,
        before siblingID: FolderID? = nil, beforeTabID: TabID? = nil
    ) -> Bool {
        guard space(matching: assignment) != nil,
            session.moveFolder(
                id, in: assignment.spaceID, into: parentID, before: siblingID,
                location: location, beforeTabID: beforeTabID)
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }
}
