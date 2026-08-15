import Foundation

/// A bounded, order-preserving view over a Space's folder forest. Runtime repair,
/// sync, import/export, menus, and both adaptive sidebars share this one topology.
struct BrowserFolderTree: Equatable, Sendable {
    let folders: [SavedFolder]

    private let foldersByID: [FolderID: SavedFolder]
    private let rootFolders: [SavedFolder]
    private let childrenByParentID: [FolderID: [SavedFolder]]

    init(folders: [SavedFolder]) {
        self.folders = folders
        var foldersByID: [FolderID: SavedFolder] = [:]
        var rootFolders: [SavedFolder] = []
        var childrenByParentID: [FolderID: [SavedFolder]] = [:]

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
              foldersByID.count == folders.count else { return false }
        for folder in folders {
            if let parentID = folder.parentID,
               parentID == folder.id || foldersByID[parentID] == nil {
                return false
            }
        }
        let nodes = flattenedNodes(collapsedFolderIDs: [])
        return nodes.count == folders.count
            && nodes.allSatisfy { $0.depth < BrowserSpace.maximumFolderDepth }
    }

    var foldersInDisplayOrder: [SavedFolder] {
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

    func children(of folderID: FolderID?) -> [SavedFolder] {
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
                  let parent = foldersByID[parentID] else { return nil }
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
                  let parent = foldersByID[parentID] else { return nil }
            titles.append(parent.title)
            folder = parent
        }
        return titles.reversed().joined(separator: " › ")
    }

    static func repairedPreorder(_ source: [SavedFolder]) -> [SavedFolder] {
        var accepted: [SavedFolder] = []
        var depthByID: [FolderID: Int] = [:]
        accepted.reserveCapacity(min(source.count, BrowserSpace.maximumFolderCount))

        for folder in source.prefix(BrowserSpace.maximumFolderCount) {
            let parentID: FolderID? = if let requestedParentID = folder.parentID,
                                         let parentDepth = depthByID[requestedParentID],
                                         parentDepth + 1 < BrowserSpace.maximumFolderDepth,
                                         requestedParentID != folder.id {
                requestedParentID
            } else {
                nil
            }
            let repaired = SavedFolder(
                id: folder.id,
                title: folder.title,
                symbol: folder.symbol,
                color: folder.color,
                parentID: parentID,
                isCollapsed: folder.isCollapsed,
                collapseModifiedAt: folder.collapseModifiedAt
            )
            accepted.append(repaired)
            depthByID[repaired.id] = parentID.flatMap { depthByID[$0] }.map { $0 + 1 } ?? 0
        }
        return BrowserFolderTree(folders: accepted).foldersInDisplayOrder
    }

    private func append(
        _ folder: SavedFolder,
        depth: Int,
        collapsedFolderIDs: Set<FolderID>,
        visited: inout Set<FolderID>,
        result: inout [BrowserFolderNode]
    ) {
        guard depth < BrowserSpace.maximumFolderDepth,
              visited.insert(folder.id).inserted else { return }
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
