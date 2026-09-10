import Foundation

extension BrowserSession {
    /// Folder batches move containers, not just their visible tabs. Work stays
    /// in applyTabBatch's draft until every destination has passed validation.
    mutating func applyFolderBatch(
        _ request: BrowserTabBatchRequest, action: BrowserTabBatchAction, at date: Date
    ) throws -> BrowserTabBatchResult {
        switch action {
        case .file(let placement, let parent, let before, let beforeFolder):
            try fileFolderBatch(
                request, placement: placement, parent: parent, before: before,
                beforeFolder: beforeFolder, at: date)
        case .newFolder(let location):
            guard let folder = addFolder(location: location, in: request.assignment.spaceID) else {
                throw BrowserTabBatchError.invalidDestination
            }
            try fileFolderBatch(request, placement: location.tabPlacement, parent: folder, at: date)
        case .keepLoaded:
            // Page operations can address contained tabs without changing the tree.
            if !request.ids.isEmpty, let source = space(id: request.assignment.spaceID) {
                _ = try applyTabBatch(BrowserTabBatchRequest(ids: request.ids, in: source), action: action, at: date)
            }
        default: throw BrowserTabBatchError.folderActionUnavailable
        }
        return BrowserTabBatchResult()
    }

    private mutating func fileFolderBatch(
        _ request: BrowserTabBatchRequest, placement: TabPlacement, parent: FolderID?,
        before: TabID? = nil, beforeFolder: FolderID? = nil, at date: Date
    ) throws {
        guard placement != .pinned, let source = space(id: request.assignment.spaceID),
            parent.map({ !request.folderIDs.contains($0) }) ?? true,
            before.map({ !request.ids.contains($0) }) ?? true,
            beforeFolder.map({ !request.folderIDs.contains($0) }) ?? true
        else { throw BrowserTabBatchError.invalidDestination }
        let location: BrowserFolderLocation = placement == .current ? .current : .saved
        guard parent.map({ id in source.folders.contains { $0.id == id && $0.location == location } }) ?? true,
            beforeFolder.map({ id in
                source.folders.contains {
                    $0.id == id && $0.parentID == parent && $0.location == location
                }
            }) ?? true,
            beforeFolder != nil
                || before.map({ id in
                    source.tabs.contains {
                        $0.id == id && $0.folderID == parent && $0.placement == placement
                            && (source.splitGroup(containing: id).map {
                                source.splitGroupMembers(of: $0).first?.id == id
                            } ?? true)
                    }
                }) ?? true
        else { throw BrowserTabBatchError.invalidDestination }
        for id in request.rootItems.compactMap(\.folderID) {
            guard canMoveFolder(id, in: source.id, into: parent) else {
                throw BrowserTabBatchError.invalidDestination
            }
        }
        var blocks: [(item: BrowserSelectionItemID, tabs: [TabID])] = []
        var included: Set<TabID> = []
        for item in request.rootItems {
            switch item {
            case .folder: blocks.append((item, []))
            case .tab(let id):
                guard !included.contains(id) else { continue }
                let ids = source.splitGroup(containing: id).map { source.splitGroupMembers(of: $0).map(\.id) } ?? [id]
                included.formUnion(ids)
                blocks.append((item, ids))
            }
        }
        var tabAnchor = before
        var folderAnchor = beforeFolder
        // Insert backwards against the preceding moved block. This retains the
        // relative order of tabs, empty folders, filled folders and whole splits.
        for block in blocks.reversed() {
            switch block.item {
            case .folder(let id):
                // All topology and anchor guards are checked above. These APIs
                // also return false for an already correctly placed item.
                _ = moveFolder(
                    id, in: source.id, into: parent, before: folderAnchor,
                    location: location, beforeTabID: tabAnchor, at: date)
                folderAnchor = id
                tabAnchor = nil
            case .tab:
                _ = fileTabs(
                    block.tabs, in: source.id, into: parent, location: location,
                    before: tabAnchor, beforeFolderID: folderAnchor, at: date)
                tabAnchor = block.tabs.first
                folderAnchor = nil
            }
        }
        guard let result = space(id: source.id), result.folderTree.isValid,
            request.rootItems.allSatisfy({ item in
                switch item {
                case .folder(let id):
                    result.folders.contains { $0.id == id && $0.parentID == parent && $0.location == location }
                case .tab(let id):
                    result.tabs.contains { $0.id == id && $0.folderID == parent && $0.placement == placement }
                }
            })
        else { throw BrowserTabBatchError.invalidDestination }
    }
}
