import Foundation

extension BrowserSession {
    mutating func preserveFolderOrder(in spaceIndex: Int, removing tabIDs: Set<TabID>) {
        guard !tabIDs.isEmpty else { return }
        let space = spaces[spaceIndex]
        spaces[spaceIndex].folders = space.folderTree.preservingOrder(removing: tabIDs, tabs: space.tabs)
    }

    /// Moves the existing subtree. Folder and tab identities never change when
    /// placement changes; callers publish this transaction once.
    @discardableResult
    mutating func moveFolder(
        _ folderID: FolderID, in spaceID: SpaceID, into parentID: FolderID?,
        before siblingID: FolderID? = nil, location: BrowserFolderLocation? = nil,
        beforeTabID: TabID? = nil, at date: Date = .now
    ) -> Bool {
        guard canMoveFolder(folderID, in: spaceID, into: parentID),
            let index = spaces.firstIndex(where: { $0.id == spaceID }),
            let source = spaces[index].folders.first(where: { $0.id == folderID })
        else { return false }
        let space = spaces[index]
        let tree = space.folderTree
        let movingIDs = tree.descendants(of: folderID).union([folderID])
        let destination =
            parentID.flatMap { id in space.folders.first { $0.id == id }?.location }
            ?? location ?? source.location
        guard
            siblingID.map({ id in
                !movingIDs.contains(id)
                    && space.folders.contains {
                        $0.id == id && $0.parentID == parentID && $0.location == destination
                    }
            }) ?? true
        else { return false }
        let members = space.tabs.filter { $0.folderID.map(movingIDs.contains) == true }
        let memberIDs = Set(members.map(\.id))
        guard
            beforeTabID.map({ id in
                !memberIDs.contains(id)
                    && space.tabs.contains { $0.id == id && $0.placement == destination.tabPlacement }
            }) ?? true
        else { return false }
        var next = space
        next.folders = tree.preservingOrder(removing: memberIDs, tabs: space.tabs, excluding: movingIDs)
        let remainingTabs = space.tabs.filter { !memberIDs.contains($0.id) }
        let remainingTree = BrowserFolderTree(folders: next.folders)
        let anchor = siblingID.map { remainingTree.tabAnchor(before: $0, tabs: remainingTabs) } ?? beforeTabID
        let emptyPredecessors = remainingTree.emptyFolders(
            before: siblingID, anchor: anchor, parentID: parentID, location: destination, tabs: remainingTabs)
        var moving = space.folders.filter { movingIDs.contains($0.id) }
        for i in moving.indices {
            moving[i].location = destination
            if moving[i].id == folderID {
                moving[i].parentID = parentID
                moving[i].orderAnchorTabID = anchor
            }
        }
        next.folders.removeAll { movingIDs.contains($0.id) }
        let folderInsertion: Int
        if let siblingID, let i = next.folders.firstIndex(where: { $0.id == siblingID }) {
            folderInsertion = i
        } else if let parentID {
            let parentIDs = tree.descendants(of: parentID).union([parentID])
            folderInsertion =
                next.folders.lastIndex { parentIDs.contains($0.id) }.map { $0 + 1 } ?? next.folders.endIndex
        } else {
            folderInsertion = next.folders.endIndex
        }
        next.folders.insert(contentsOf: moving, at: folderInsertion)
        next.folders = BrowserFolderTree(folders: next.folders).foldersInDisplayOrder
        do {
            next.tabs.removeAll { memberIDs.contains($0.id) }
            let insertion: Int
            if let anchor, let i = next.tabs.firstIndex(where: { $0.id == anchor }) {
                insertion = i
            } else if let parentID,
                let last = next.tabs.lastIndex(where: {
                    $0.folderID.map(tree.descendants(of: parentID).union([parentID]).contains) == true
                })
            {
                insertion = last + 1
            } else {
                insertion =
                    next.tabs.lastIndex { $0.placement == destination.tabPlacement }.map { $0 + 1 }
                    ?? (destination == .saved ? next.tabs.firstIndex { $0.placement == .current } : nil)
                    ?? next.tabs.endIndex
            }
            if insertion > 0, insertion < next.tabs.count, let split = next.tabs[insertion].splitGroupID,
                next.tabs[insertion - 1].splitGroupID == split
            {
                return false
            }
            let placed = members.map { tab in
                var value = tab
                value.placement = destination.tabPlacement
                value.savedURL = destination == .current ? nil : value.savedURL ?? value.url
                value.markPositionModified(at: date)
                return value
            }
            next.tabs.insert(contentsOf: placed, at: insertion)
        }
        if let first = members.first?.id {
            for i in next.folders.indices
            where emptyPredecessors.contains(next.folders[i].id) && !movingIDs.contains(next.folders[i].id) {
                next.folders[i].orderAnchorTabID = first
            }
        }
        guard next != space else { return false }
        spaces[index] = next
        return true
    }

    /// A common folder-membership transaction for menus, drops and extensions.
    /// Split members travel together, in their existing page order.
    @discardableResult
    mutating func fileTabs(
        _ tabIDs: [TabID], in spaceID: SpaceID, into folderID: FolderID?,
        location: BrowserFolderLocation, before requestedAnchorID: TabID? = nil,
        beforeFolderID: FolderID? = nil, at date: Date = .now
    ) -> Bool {
        guard !tabIDs.isEmpty, let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return false }
        let space = spaces[index]
        let byID = Dictionary(uniqueKeysWithValues: space.tabs.map { ($0.id, $0) })
        guard tabIDs.allSatisfy({ byID[$0] != nil }),
            folderID == nil || space.folders.contains(where: { $0.id == folderID && $0.location == location })
        else { return false }
        let tree = space.folderTree
        if let beforeFolderID {
            guard
                space.folders.contains(where: {
                    $0.id == beforeFolderID && $0.parentID == folderID && $0.location == location
                })
            else { return false }
        }
        let splits = Set(tabIDs.compactMap { byID[$0]?.splitGroupID })
        let requested = Set(tabIDs)
        let members = space.tabs.filter { requested.contains($0.id) || $0.splitGroupID.map(splits.contains) == true }
        let memberIDs = Set(members.map(\.id))
        var remaining = space.tabs.filter { !memberIDs.contains($0.id) }
        var folders = tree.preservingOrder(removing: memberIDs, tabs: space.tabs)
        let remainingTree = BrowserFolderTree(folders: folders)
        let anchorID = beforeFolderID.map { remainingTree.tabAnchor(before: $0, tabs: remaining) } ?? requestedAnchorID
        let emptyPredecessors = remainingTree.emptyFolders(
            before: beforeFolderID, anchor: anchorID, parentID: folderID, location: location, tabs: remaining)
        guard
            anchorID.map({ id in
                !memberIDs.contains(id) && space.tabs.contains { $0.id == id && $0.placement == location.tabPlacement }
            }) ?? true
        else { return false }
        let insertion: Int
        if let anchorID, let i = remaining.firstIndex(where: { $0.id == anchorID }) {
            insertion = i
        } else if let folderID, let last = remaining.lastIndex(where: { $0.folderID == folderID }) {
            insertion = last + 1
        } else {
            // Creating a group preserves its first member's position. Moving
            // out of one appends to the destination section.
            insertion =
                folderID == nil
                ? (remaining.lastIndex { $0.placement == location.tabPlacement }.map { $0 + 1 }
                    ?? BrowserTabPlacementDestinationSection(placement: location.tabPlacement, folderID: nil)
                    .insertionIndex(before: nil, in: remaining))
                : min(space.tabs.firstIndex { memberIDs.contains($0.id) } ?? remaining.endIndex, remaining.endIndex)
        }
        if insertion > 0, insertion < remaining.count, let split = remaining[insertion].splitGroupID,
            remaining[insertion - 1].splitGroupID == split
        {
            return false
        }
        let moved = members.map { tab in
            var value = tab
            value.placement = location.tabPlacement
            value.folderID = folderID
            value.savedURL = location == .current ? nil : value.savedURL ?? value.url
            return value
        }
        remaining.insert(contentsOf: moved, at: insertion)
        for i in folders.indices where emptyPredecessors.contains(folders[i].id) {
            folders[i].orderAnchorTabID = members.first?.id
        }
        guard remaining != space.tabs || folders != space.folders else { return false }
        for i in remaining.indices where memberIDs.contains(remaining[i].id) {
            remaining[i].markPositionModified(at: date)
        }
        spaces[index].tabs = remaining
        spaces[index].folders = folders
        return true
    }

    @discardableResult
    mutating func createTabFolder(
        _ tabIDs: [TabID], in spaceID: SpaceID, location: BrowserFolderLocation = .current,
        title: String = "New Folder", color: BrowserSpaceBrandColor = .folderDefault
    ) -> FolderID? {
        var next = self
        guard let space = space(id: spaceID), !tabIDs.isEmpty,
            tabIDs.allSatisfy({ id in space.tabs.contains { $0.id == id } }),
            let folderID = next.addFolder(title: title, color: color, location: location, in: spaceID),
            next.fileTabs(tabIDs, in: spaceID, into: folderID, location: location)
        else { return nil }
        self = next
        return folderID
    }
}
