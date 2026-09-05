import Foundation

/// A bounded, order-preserving view over a Space's folder forest. Runtime repair,
/// sync, import/export, menus, and both adaptive sidebars share this one topology.
struct BrowserFolderTree: Equatable, Sendable {
    let folders: [BrowserFolder]

    private let foldersByID: [FolderID: BrowserFolder]
    private let rootFolders: [BrowserFolder]
    private let childrenByParentID: [FolderID: [BrowserFolder]]

    init(folders: [BrowserFolder]) {
        self.folders = folders
        var foldersByID: [FolderID: BrowserFolder] = [:]
        var rootFolders: [BrowserFolder] = []
        var childrenByParentID: [FolderID: [BrowserFolder]] = [:]

        for folder in folders where foldersByID[folder.id] == nil {
            foldersByID[folder.id] = folder
            if let parentID = folder.parentID {
                childrenByParentID[parentID, default: []].append(folder)
            } else {
                rootFolders.append(folder)
            }
        }

        self.foldersByID = foldersByID
        self.rootFolders = rootFolders
        self.childrenByParentID = childrenByParentID
    }

    var isValid: Bool {
        guard folders.count <= BrowserSpace.maximumFolderCount,
            foldersByID.count == folders.count
        else { return false }
        for folder in folders {
            if let parentID = folder.parentID,
                parentID == folder.id || foldersByID[parentID] == nil
                    || foldersByID[parentID]?.location != folder.location
            {
                return false
            }
        }
        let nodes = flattenedNodes(collapsedFolderIDs: [])
        return nodes.count == folders.count
            && nodes.allSatisfy { $0.depth < BrowserSpace.maximumFolderDepth }
    }

    var foldersInDisplayOrder: [BrowserFolder] {
        flattenedNodes(collapsedFolderIDs: []).map(\.folder)
    }

    func flattenedNodes(collapsedFolderIDs: Set<FolderID>) -> [BrowserFolderNode] {
        var result: [BrowserFolderNode] = []
        var visited: Set<FolderID> = []
        for folder in rootFolders {
            append(
                folder,
                depth: 0,
                collapsedFolderIDs: collapsedFolderIDs,
                visited: &visited,
                result: &result
            )
        }
        return result
    }

    func children(of folderID: FolderID?) -> [BrowserFolder] {
        guard let folderID else { return rootFolders }
        return childrenByParentID[folderID] ?? []
    }

    func descendants(of folderID: FolderID) -> Set<FolderID> {
        var result: Set<FolderID> = []
        var pending = childrenByParentID[folderID] ?? []
        while let child = pending.popLast() {
            guard result.insert(child.id).inserted else { continue }
            pending.append(contentsOf: childrenByParentID[child.id] ?? [])
        }
        return result
    }

    func depth(of folderID: FolderID) -> Int? {
        guard var folder = foldersByID[folderID] else { return nil }
        var depth = 0
        var visited: Set<FolderID> = [folder.id]
        while let parentID = folder.parentID {
            guard depth + 1 < BrowserSpace.maximumFolderDepth,
                visited.insert(parentID).inserted,
                let parent = foldersByID[parentID]
            else { return nil }
            depth += 1
            folder = parent
        }
        return depth
    }

    func pathTitle(for folderID: FolderID) -> String? {
        guard var folder = foldersByID[folderID] else { return nil }
        var titles = [folder.title]
        var visited: Set<FolderID> = [folder.id]
        while let parentID = folder.parentID {
            guard visited.insert(parentID).inserted,
                let parent = foldersByID[parentID]
            else { return nil }
            titles.append(parent.title)
            folder = parent
        }
        return titles.reversed().joined(separator: " › ")
    }

    static func repairedPreorder(_ source: [BrowserFolder]) -> [BrowserFolder] {
        var accepted: [BrowserFolder] = []
        var depthByID: [FolderID: Int] = [:]
        accepted.reserveCapacity(min(source.count, BrowserSpace.maximumFolderCount))

        for folder in source.prefix(BrowserSpace.maximumFolderCount) {
            let parentID: FolderID? =
                if let requestedParentID = folder.parentID,
                    let parentDepth = depthByID[requestedParentID],
                    parentDepth + 1 < BrowserSpace.maximumFolderDepth,
                    requestedParentID != folder.id
                {
                    requestedParentID
                } else {
                    nil
                }
            let repaired = BrowserFolder(
                id: folder.id,
                title: folder.title,
                location: parentID.flatMap { id in accepted.first { $0.id == id }?.location } ?? folder.location,
                symbol: folder.symbol,
                color: folder.color,
                parentID: parentID,
                isCollapsed: folder.isCollapsed,
                collapseModifiedAt: folder.collapseModifiedAt,
                orderAnchorTabID: folder.orderAnchorTabID
            )
            accepted.append(repaired)
            depthByID[repaired.id] = parentID.flatMap { depthByID[$0] }.map { $0 + 1 } ?? 0
        }
        return BrowserFolderTree(folders: accepted).foldersInDisplayOrder
    }

    func tabAnchor(before folderID: FolderID, tabs: [BrowserTab]) -> TabID? {
        let ids = descendants(of: folderID).union([folderID])
        return tabs.first { $0.folderID.map(ids.contains) == true }?.id
            ?? foldersByID[folderID]?.orderAnchorTabID.flatMap { anchor in
                tabs.first { $0.id == anchor }?.id
            }
    }

    /// Empty siblings share a boundary in the tab sequence. A drop between
    /// them moves only the preceding siblings to the start of the inserted run.
    func emptyFolders(
        before folderID: FolderID?, anchor: TabID?, parentID: FolderID?,
        location: BrowserFolderLocation, tabs: [BrowserTab]
    ) -> Set<FolderID> {
        var result: Set<FolderID> = []
        let targetSubtree = folderID.map { descendants(of: $0).union([$0]) } ?? []
        let targetIsEmpty = !tabs.contains { $0.folderID.map(targetSubtree.contains) == true }
        for folder in children(of: parentID) where folder.location == location {
            if folder.id == folderID && targetIsEmpty { break }
            let ids = descendants(of: folder.id).union([folder.id])
            if !tabs.contains(where: { $0.folderID.map(ids.contains) == true }),
                tabAnchor(before: folder.id, tabs: tabs) == anchor
            {
                result.insert(folder.id)
            }
        }
        return result
    }

    /// Keep an empty subtree at its original boundary when its anchor or last
    /// member leaves. Stable tab IDs avoid storing a second ordered tab list.
    func preservingOrder(removing removed: Set<TabID>, tabs: [BrowserTab], excluding: Set<FolderID> = [])
        -> [BrowserFolder]
    {
        folders.map { folder in
            guard !excluding.contains(folder.id) else { return folder }
            let subtree = descendants(of: folder.id).union([folder.id])
            let members = tabs.filter { $0.folderID.map(subtree.contains) == true }
            guard members.allSatisfy({ removed.contains($0.id) }) else { return folder }
            let oldAnchor = members.first?.id ?? folder.orderAnchorTabID
            guard let oldAnchor, removed.contains(oldAnchor),
                let start = tabs.firstIndex(where: { $0.id == oldAnchor })
            else { return folder }
            let parentSubtree = folder.parentID.map { descendants(of: $0).union([$0]) }
            var updated = folder
            updated.orderAnchorTabID =
                tabs.dropFirst(start).first {
                    !removed.contains($0.id) && $0.placement == folder.location.tabPlacement
                        && (parentSubtree == nil || $0.folderID.map { parentSubtree!.contains($0) } == true)
                }?.id
            return updated
        }
    }

    private func append(
        _ folder: BrowserFolder,
        depth: Int,
        collapsedFolderIDs: Set<FolderID>,
        visited: inout Set<FolderID>,
        result: inout [BrowserFolderNode]
    ) {
        guard depth < BrowserSpace.maximumFolderDepth,
            visited.insert(folder.id).inserted
        else { return }
        let children = childrenByParentID[folder.id] ?? []
        result.append(
            BrowserFolderNode(
                folder: folder,
                depth: depth,
                hasChildren: !children.isEmpty
            )
        )
        guard !collapsedFolderIDs.contains(folder.id) else { return }
        for child in children {
            append(
                child,
                depth: depth + 1,
                collapsedFolderIDs: collapsedFolderIDs,
                visited: &visited,
                result: &result
            )
        }
    }
}
