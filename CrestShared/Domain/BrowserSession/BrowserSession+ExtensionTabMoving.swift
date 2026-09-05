import Foundation

extension BrowserSession {
    /// Resolves Chrome's flat indices onto the existing folder/placement model.
    /// The caller publishes one transaction, including a multi-tab move.
    mutating func moveExtensionTabs(_ ids: [TabID], in spaceID: SpaceID, to index: Int, at date: Date = .now) -> Bool {
        guard index >= -1, !ids.isEmpty, let space = space(id: spaceID),
            ids.allSatisfy({ id in space.tabs.contains { $0.id == id } })
        else { return false }
        var next = self
        var insertion = index
        for id in ids {
            guard let actual = next.moveExtensionTab(id, in: spaceID, to: insertion, at: date) else { return false }
            insertion = actual + 1
        }
        self = next
        return true
    }

    private mutating func moveExtensionTab(_ id: TabID, in spaceID: SpaceID, to index: Int, at date: Date) -> Int? {
        guard let si = spaces.firstIndex(where: { $0.id == spaceID }),
            let sourceIndex = spaces[si].tabs.firstIndex(where: { $0.id == id })
        else { return nil }
        let space = spaces[si]
        var remaining = space.tabs
        let source = remaining.remove(at: sourceIndex)
        var slot = index == -1 ? remaining.count : min(index, remaining.count)
        let pinnedCount = remaining.filter { $0.placement == .pinned }.count
        slot = source.placement == .pinned ? min(slot, pinnedCount) : max(slot, pinnedCount)
        if slot == sourceIndex { return sourceIndex }
        let left = slot > 0 ? remaining[slot - 1] : nil
        let right = slot < remaining.count ? remaining[slot] : nil
        var folderID = source.folderID
        if folderID != left?.folderID && folderID != right?.folderID {
            folderID = left?.folderID == right?.folderID ? left?.folderID : nil
        }
        // A singleton group moves as its existing folder, preserving its ID,
        // name and color. Hierarchies still use the shared subtree transaction.
        if let sourceFolder = source.folderID, folderID == nil,
            !remaining.contains(where: { $0.folderID == sourceFolder }),
            space.folderTree.descendants(of: sourceFolder).isEmpty,
            let folder = space.folders.first(where: { $0.id == sourceFolder })
        {
            let sibling = right?.folderID.flatMap { fid in space.folders.first { $0.id == fid } }
            let location: BrowserFolderLocation = (right ?? left)?.placement == .saved ? .saved : .current
            let parentID = location == folder.location ? folder.parentID : nil
            guard sibling == nil || sibling?.parentID == parentID,
                moveFolder(
                    sourceFolder, in: spaceID, into: parentID, before: sibling?.id,
                    location: location, beforeTabID: right?.id, at: date)
            else { return nil }
            return spaces[si].tabs.firstIndex { $0.id == id }
        }
        let placement: TabPlacement
        if source.placement == .pinned {
            placement = .pinned
            folderID = nil
        } else if let folder = space.folders.first(where: { $0.id == folderID }) {
            placement = folder.location.tabPlacement
        } else {
            placement = (right ?? left)?.placement == .saved ? .saved : .current
        }
        guard
            let plan = BrowserTabPlacementPlan(
                moving: source, to: placement, folderID: folderID,
                requestedIndex: slot, in: space, among: remaining)
        else { return nil }
        var moved = plan.placing(source)
        moved.markPositionModified(at: date)
        remaining.insert(moved, at: plan.insertionIndex)
        preserveFolderOrder(in: si, removing: [id])
        spaces[si].tabs = BrowserSplitGroupNormalizer.normalized(remaining)
        return plan.insertionIndex
    }
}
