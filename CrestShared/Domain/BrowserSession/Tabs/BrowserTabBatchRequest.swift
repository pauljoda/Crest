import Foundation

enum BrowserSelectionItemID: Codable, Hashable, Sendable {
    case tab(TabID)
    case folder(FolderID)

    var tabID: TabID? {
        if case .tab(let id) = self { return id }
        return nil
    }
    var folderID: FolderID? {
        if case .folder(let id) = self { return id }
        return nil
    }
}

/// Captures membership and placement at the start of a menu or drag.
struct BrowserTabBatchRequest: Codable, Equatable, Sendable {
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

    let assignment: BrowserSpaceRuntimeAssignment
    let members: [Member]
    let folders: [FolderMember]
    let rootItems: [BrowserSelectionItemID]
    var ids: [TabID] { members.map(\.id) }
    var folderIDs: Set<FolderID> { Set(folders.map(\.id)) }
    var hasFolders: Bool { !folders.isEmpty }

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

    func validate(in session: BrowserSession) throws -> BrowserSpace {
        guard !rootItems.isEmpty, Set(rootItems).count == rootItems.count, Set(ids).count == ids.count,
            let space = session.space(id: assignment.spaceID), assignment.matches(space)
        else { throw BrowserTabBatchError.staleSelection }
        guard
            rootItems.allSatisfy({ item in
                switch item {
                case .tab(let id): space.tabs.contains { $0.id == id }
                case .folder(let id): space.folders.contains { $0.id == id }
                }
            }), BrowserTabBatchRequest(items: rootItems, in: space) == self
        else {
            throw BrowserTabBatchError.staleSelection
        }
        let tabs = Dictionary(uniqueKeysWithValues: space.tabs.map { ($0.id, $0) })
        for member in members {
            guard let tab = tabs[member.id], Member(tab) == member, !tab.isStartPage else {
                throw BrowserTabBatchError.staleSelection
            }
            if let group = space.splitGroup(containing: member.id),
                !Set(space.splitGroupMembers(of: group).map(\.id)).isSubset(of: Set(ids))
            {
                throw BrowserTabBatchError.incompleteSplit
            }
        }
        return space
    }
}

enum BrowserTabBatchAction: Equatable, Sendable {
    case file(TabPlacement, folder: FolderID? = nil, before: TabID? = nil, beforeFolder: FolderID? = nil)
    case newFolder(BrowserFolderLocation)
    case newFolderAround(TabID)
    case moveToSpace(BrowserSpaceRuntimeAssignment)
    case split(joining: TabID? = nil, at: Int? = nil)
    case close
    case delete
    case duplicate
    case keepLoaded(Bool)
    case separateSplits
}

enum BrowserTabBatchError: Error, Equatable {
    case staleSelection, lockedSpace, incompleteSplit, pinnedCapacity, splitCapacity
    case folderActionUnavailable
    case cannotPinSplit, cannotMoveSplitAcrossSpaces, currentTabsOnly, webPagesOnly, invalidDestination
}

struct BrowserTabBatchResult {
    var copies: [(source: TabID, copy: TabID)] = []
}
