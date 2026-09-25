import Foundation

/// A bounded, order-preserving view over a Space's folder forest of the
/// session copy, for sync, import and export and the command palette. The
/// sidebar reads the core's outline instead.
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
        let walked = preorder()
        return walked.count == folders.count
            && walked.allSatisfy { $0.depth < BrowserSpace.maximumFolderDepth }
    }

    /// Every folder, each parent before its children, as import, export and
    /// the command palette list them. The sidebar lists the core's outline.
    var foldersInDisplayOrder: [BrowserFolder] {
        preorder().map(\.folder)
    }

    func children(of folderID: FolderID?) -> [BrowserFolder] {
        guard let folderID else { return rootFolders }
        return childrenByParentID[folderID] ?? []
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

    /// The folders reachable from the roots, each parent before its
    /// children, with their depth, stopping at the depth a Space allows and
    /// at any folder met twice.
    private func preorder() -> [(folder: BrowserFolder, depth: Int)] {
        var result: [(folder: BrowserFolder, depth: Int)] = []
        var visited: Set<FolderID> = []
        func walk(_ folder: BrowserFolder, depth: Int) {
            guard depth < BrowserSpace.maximumFolderDepth, visited.insert(folder.id).inserted else { return }
            result.append((folder, depth))
            for child in childrenByParentID[folder.id] ?? [] { walk(child, depth: depth + 1) }
        }
        for folder in rootFolders { walk(folder, depth: 0) }
        return result
    }
}
