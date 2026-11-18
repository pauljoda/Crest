import Foundation

/// What a person changed in setup's copy of the browser, as its tabs and
/// folders stand against the session the copy opened on, Space by Space: the
/// tabs they deleted, the folders they made, changed or deleted, and every
/// list of tabs whose tabs or order they changed. `replay(into:)` makes the
/// same changes to a browser that holds those Spaces, tabs and folders, as
/// the one setup finishes into, or a copy opened again, does: setup's import
/// keeps the tabs and folders the copy showed under the same identities.
/// Whatever that browser no longer holds, or refuses, is left out.
struct BrowserSetupCopyEdits: Equatable {
    // MARK: - Types

    /// The tabs of a section's top level or of a folder, in order.
    struct TabList: Equatable {
        let placement: TabPlacement
        let folderID: UUID?
        let tabIDs: [UUID]
    }

    /// The changes to one Space.
    struct SpaceEdits: Equatable {
        let spaceID: UUID
        var deletedTabIDs: [UUID] = []
        var deletedFolderIDs: [UUID] = []
        /// Folders made in the copy, each after the folder it sits in.
        var madeFolders: [FolderState] = []
        /// Folders the copy kept but renamed, recolored, gave a new icon or
        /// moved.
        var changedFolders: [FolderState] = []
        /// Each list of tabs whose tabs or order changed, as the copy left it.
        var rearrangedLists: [TabList] = []

        var isEmpty: Bool {
            deletedTabIDs.isEmpty && deletedFolderIDs.isEmpty && madeFolders.isEmpty && changedFolders.isEmpty
                && rearrangedLists.isEmpty
        }
    }

    // MARK: - Variables

    /// The Spaces the person changed.
    let spaces: [SpaceEdits]

    var isEmpty: Bool { spaces.isEmpty }

    // MARK: - Initializers

    /// The changes the copy's Spaces, `current`, hold against `opened`, the
    /// session the copy opened on.
    init(from opened: SessionState.Seed, to current: [SpaceState]) {
        spaces = current.compactMap { space in
            guard let was = opened.spaces.first(where: { $0.id == space.id }) else { return nil }
            let edits = Self.edits(from: was, to: space)
            return edits.isEmpty ? nil : edits
        }
    }

    // MARK: - Actions - Replaying

    /// Makes the same changes to `store`'s browser: deletes the tabs, then
    /// the folders, makes and changes the folders, and lays out each list of
    /// tabs from its last tab back, each before the one after it.
    @MainActor
    func replay(into store: BrowserStore) {
        let workspaceID = store.family.workspaceID
        for edits in spaces {
            guard let space = store.spaceModels.first(where: { $0.id == edits.spaceID })?.value else { continue }
            let spaceID = space.id
            let tabIDs = Set(space.tabs.map(\.id))
            let folderIDs = Set(space.folders.map(\.id))
            for tabID in edits.deletedTabIDs where tabIDs.contains(tabID) {
                _ = try? store.core.send(
                    DeleteTab(workspaceID: workspaceID, windowID: store.windowID, spaceID: spaceID, tabID: tabID))
            }
            for folderID in edits.deletedFolderIDs where folderIDs.contains(folderID) {
                _ = try? store.core.send(DeleteFolder(workspaceID: workspaceID, spaceID: spaceID, folderID: folderID))
            }
            for folder in edits.madeFolders where !folderIDs.contains(folder.id) {
                let inside =
                    edits.rearrangedLists.first { $0.folderID == folder.id }?.tabIDs.filter(tabIDs.contains) ?? []
                _ = try? store.core.send(
                    CreateFolder(
                        workspaceID: workspaceID, spaceID: spaceID, folderID: folder.id, placement: folder.location,
                        parentID: folder.parentID, title: folder.title, color: folder.color, symbol: folder.symbol,
                        tabIDs: inside, leavesSplits: false, isGroup: folder.isGroup))
            }
            for folder in edits.changedFolders where folderIDs.contains(folder.id) {
                change(folder, of: spaceID, in: store)
            }
            for list in edits.rearrangedLists {
                var after: UUID?
                for tabID in list.tabIDs.filter(tabIDs.contains).reversed() {
                    _ = try? store.core.send(
                        MoveTab(
                            workspaceID: workspaceID, spaceID: spaceID, tabID: tabID, placement: list.placement,
                            folderID: list.folderID, beforeTabID: after, leavesSplit: false))
                    after = tabID
                }
            }
        }
    }

    /// Gives the folder `folder` names in `spaceID` its title, color, icon
    /// and place.
    @MainActor
    private func change(_ folder: FolderState, of spaceID: UUID, in store: BrowserStore) {
        let workspaceID = store.family.workspaceID
        _ = try? store.core.send(
            RenameFolder(workspaceID: workspaceID, spaceID: spaceID, folderID: folder.id, title: folder.title))
        if let color = folder.color {
            _ = try? store.core.send(
                SetFolderColor(workspaceID: workspaceID, spaceID: spaceID, folderID: folder.id, color: color))
        }
        if let symbol = folder.symbol {
            _ = try? store.core.send(
                SetFolderSymbol(workspaceID: workspaceID, spaceID: spaceID, folderID: folder.id, symbol: symbol))
        }
        _ = try? store.core.send(
            MoveFolder(
                workspaceID: workspaceID, spaceID: spaceID, folderID: folder.id, placement: folder.location,
                parentID: folder.parentID, beforeFolderID: nil, beforeTabID: nil))
    }

    // MARK: - Actions - Comparing

    private static func edits(from was: SpaceState.Seed, to space: SpaceState) -> SpaceEdits {
        var edits = SpaceEdits(spaceID: space.id)
        let tabIDs = Set(space.tabs.map(\.id))
        edits.deletedTabIDs = was.tabs.map(\.id).filter { !tabIDs.contains($0) }
        let folderIDs = Set(space.folders.map(\.id))
        edits.deletedFolderIDs = was.folders.map(\.id).filter { !folderIDs.contains($0) }
        let wasFolders = Dictionary(was.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        edits.madeFolders = parentsFirst(space.folders.filter { wasFolders[$0.id] == nil })
        edits.changedFolders = space.folders.filter { folder in
            guard let before = wasFolders[folder.id] else { return false }
            return before.title != folder.title || before.color != folder.color || before.symbol != folder.symbol
                || before.parentID != folder.parentID || before.location != folder.location
        }
        let wasLists = lists(was.tabs.map { ($0.id, $0.placement, $0.folderID) })
        edits.rearrangedLists = lists(space.tabs.map { ($0.id, $0.placement, $0.folderID) }).filter { list in
            wasLists.first { $0.placement == list.placement && $0.folderID == list.folderID }?.tabIDs != list.tabIDs
        }
        return edits
    }

    /// `tabs` as lists, each section's top level and each folder, in the
    /// order their tabs first appear.
    private static func lists(_ tabs: [(id: UUID, placement: TabPlacement, folderID: UUID?)]) -> [TabList] {
        var lists: [TabList] = []
        for tab in tabs {
            if let index = lists.firstIndex(where: { $0.placement == tab.placement && $0.folderID == tab.folderID }) {
                let list = lists[index]
                lists[index] = TabList(
                    placement: list.placement, folderID: list.folderID, tabIDs: list.tabIDs + [tab.id])
            } else {
                lists.append(TabList(placement: tab.placement, folderID: tab.folderID, tabIDs: [tab.id]))
            }
        }
        return lists
    }

    /// `folders` with each after the folder among them it sits in.
    private static func parentsFirst(_ folders: [FolderState]) -> [FolderState] {
        let ids = Set(folders.map(\.id))
        var placed: Set<UUID> = []
        var ordered: [FolderState] = []
        var remaining = folders
        while !remaining.isEmpty {
            let ready = remaining.filter { folder in
                folder.parentID.map { !ids.contains($0) || placed.contains($0) } ?? true
            }
            guard !ready.isEmpty else { return ordered + remaining }
            ordered += ready
            placed.formUnion(ready.map(\.id))
            remaining.removeAll { folder in ready.contains { $0.id == folder.id } }
        }
        return ordered
    }
}
