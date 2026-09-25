import Foundation

/// A window's multi-selection as it stood when a menu opened or a drag began:
/// the Space it was made in, what the person picked that no picked folder
/// holds, and every tab and folder that takes part. Views read it to label and
/// lift the selection; the core decides every action on it through `core`.
struct BrowserTabBatchRequest: Codable, Equatable, Sendable {
    // MARK: - Types

    struct Member: Codable, Equatable, Sendable {
        let id: TabID
        let placement: TabPlacement
        let folderID: FolderID?
        let splitGroupID: SplitGroupID?

        init(_ tab: BrowserTab) {
            id = tab.id
            placement = tab.placement
            folderID = tab.folderID
            splitGroupID = tab.splitGroupID
        }
    }

    struct FolderMember: Codable, Equatable, Sendable {
        let id: FolderID
        let parentID: FolderID?
        let location: BrowserFolderLocation
        init(_ folder: BrowserFolder) {
            id = folder.id
            parentID = folder.parentID
            location = folder.location
        }
    }

    // MARK: - Variables

    let assignment: BrowserSpaceRuntimeAssignment
    let members: [Member]
    let folders: [FolderMember]
    let rootItems: [BrowserSelectionItemID]
    var ids: [TabID] { members.map(\.id) }
    var folderIDs: Set<FolderID> { Set(folders.map(\.id)) }
    var hasFolders: Bool { !folders.isEmpty }

    /// The selection as the core reads it: what the person picked, by kind,
    /// and the tabs the window saw the selection hold.
    var core: TabSelection {
        TabSelection(
            tabIDs: rootItems.compactMap(\.tabID),
            folderIDs: rootItems.compactMap(\.folderID),
            memberTabIDs: ids)
    }

    // MARK: - Initializers

    init(ids: [TabID], in space: BrowserSpace) {
        self.init(items: ids.map(BrowserSelectionItemID.tab), in: space)
    }

    init(items: [BrowserSelectionItemID], in space: BrowserSpace) {
        assignment = BrowserSpaceRuntimeAssignment(space: space)
        let tree = space.folderTree
        let selectedFolders = Set(items.compactMap(\.folderID))
        let covered = selectedFolders.reduce(into: Set<FolderID>()) { $0.formUnion(tree.descendants(of: $1)) }
        let roots = items.filter { item in
            switch item {
            case .folder(let id): return !covered.contains(id)
            case .tab(let id):
                return !space.tabs.contains {
                    $0.id == id && $0.folderID.map(selectedFolders.union(covered).contains) == true
                }
            }
        }
        rootItems = roots
        let allFolders = selectedFolders.union(covered)
        folders = space.folders.filter { allFolders.contains($0.id) }.map(FolderMember.init)
        var tabs: [BrowserTab] = []
        for root in roots {
            switch root {
            case .folder(let id):
                let subtree = tree.descendants(of: id).union([id])
                tabs += space.tabs.filter { $0.folderID.map(subtree.contains) == true }
            case .tab(let id):
                if let tab = space.tabs.first(where: { $0.id == id }) { tabs.append(tab) }
            }
        }
        members = tabs.map(Member.init)
    }
}
