import Foundation

extension BrowserSession {
    /// Validate and prepare in a value copy. No failure can publish a partial batch.
    mutating func applyTabBatch(
        _ request: BrowserTabBatchRequest, action: BrowserTabBatchAction,
        fallbackTabID: TabID? = nil, at date: Date = .now
    ) throws -> BrowserTabBatchResult {
        let source = try request.validate(in: self)
        var draft = self
        let result = try draft.prepareTabBatch(
            request, action: action, source: source, fallback: fallbackTabID, date: date)
        self = draft
        return result
    }

    private mutating func prepareTabBatch(
        _ request: BrowserTabBatchRequest, action: BrowserTabBatchAction, source: BrowserSpace,
        fallback: TabID?, date: Date
    ) throws -> BrowserTabBatchResult {
        if request.hasFolders { return try applyFolderBatch(request, action: action, at: date) }
        let ids = request.ids
        let selected = Set(ids)
        let tabs = ids.compactMap { id in source.tabs.first { $0.id == id } }
        let groupIDs = Set(tabs.compactMap { source.splitGroup(containing: $0.id) })
        var result = BrowserTabBatchResult()
        switch action {
        case .file(let placement, let folder, let before, let beforeFolder):
            if placement == .pinned {
                guard groupIDs.isEmpty else { throw BrowserTabBatchError.cannotPinSplit }
                guard
                    source.pinnedTabs.filter({ !selected.contains($0.id) }).count + ids.count
                        <= BrowserSpace.maximumPinnedTabs
                else { throw BrowserTabBatchError.pinnedCapacity }
                guard folder == nil, beforeFolder == nil else { throw BrowserTabBatchError.invalidDestination }
                guard
                    before.map({ anchor in !selected.contains(anchor) && source.pinnedTabs.contains { $0.id == anchor }
                    }) ?? true
                else { throw BrowserTabBatchError.invalidDestination }
                let oldSelection = selectedSpaceID
                selectedSpaceID = source.id
                for id in ids { _ = moveTab(id, to: .pinned, before: before, at: date) }
                selectedSpaceID = oldSelection
            } else {
                let location: BrowserFolderLocation = placement == .current ? .current : .saved
                guard before.map({ !selected.contains($0) }) ?? true,
                    folder == nil || source.folders.contains(where: { $0.id == folder && $0.location == location })
                else { throw BrowserTabBatchError.invalidDestination }
                // fileTabs preserves storage order; arrange the selected block in
                // visible order first, while keeping the surrounding rows in place.
                orderBatchMembers(ids, in: source.id)
                guard
                    fileTabs(
                        ids, in: source.id, into: folder, location: location,
                        before: before, beforeFolderID: beforeFolder, at: date)
                else {
                    throw BrowserTabBatchError.invalidDestination
                }
            }
        case .newFolder(let location):
            orderBatchMembers(ids, in: source.id)
            guard createTabFolder(ids, in: source.id, location: location) != nil else {
                throw BrowserTabBatchError.invalidDestination
            }
        case .newFolderAround(let targetID):
            guard !selected.contains(targetID), let target = source.tabs.first(where: { $0.id == targetID }),
                target.placement == .current, target.folderID == nil,
                target.splitGroupID == nil, !target.isStartPage
            else { throw BrowserTabBatchError.invalidDestination }
            let members = [targetID] + ids
            orderBatchMembers(members, in: source.id)
            guard createTabFolder(members, in: source.id, location: .current) != nil else {
                throw BrowserTabBatchError.invalidDestination
            }
        case .moveToSpace(let destination):
            guard groupIDs.isEmpty else { throw BrowserTabBatchError.cannotMoveSplitAcrossSpaces }
            guard let target = space(id: destination.spaceID), destination.matches(target), target.id != source.id
            else {
                throw BrowserTabBatchError.invalidDestination
            }
            guard
                target.pinnedTabs.count + tabs.filter({ $0.placement == .pinned }).count
                    <= BrowserSpace.maximumPinnedTabs
            else { throw BrowserTabBatchError.pinnedCapacity }
            for id in ids {
                guard moveTab(id, from: source.id, into: target.id, sourceFallbackTabID: fallback, at: date) else {
                    throw BrowserTabBatchError.invalidDestination
                }
            }
        case .split(let joining, let index):
            let targetID = joining ?? ids[0]
            guard let target = source.tabs.first(where: { $0.id == targetID }), !target.isStartPage else {
                throw BrowserTabBatchError.invalidDestination
            }
            let existing =
                source.splitGroup(containing: targetID).map { source.splitGroupMembers(of: $0).map(\.id) }
                ?? [targetID]
            let allIDs = Set(existing).union(ids)
            guard allIDs.count >= 2, allIDs.count <= BrowserSplitGroupPolicy.maximumMembers else {
                throw BrowserTabBatchError.splitCapacity
            }
            var destinationID = targetID
            var insertion = index
            for id in ids where !existing.contains(id) {
                guard
                    let copies = addTabToSplitPreservingDurableTabs(
                        id, joining: destinationID, at: insertion, in: source.id, at: date)
                else { throw BrowserTabBatchError.invalidDestination }
                result.copies.append(contentsOf: copies)
                if let copy = copies.first(where: { $0.source == destinationID }) { destinationID = copy.copy }
                if let value = insertion { insertion = value + 1 }
            }
        case .close:
            guard tabs.allSatisfy({ $0.placement == .current }) else { throw BrowserTabBatchError.currentTabsOnly }
            let oldSpace = selectedSpaceID
            selectedSpaceID = source.id
            for id in ids { closeTab(id, fallbackTabID: fallback, at: date) }
            selectedSpaceID = oldSpace
        case .delete:
            for id in ids { _ = deleteTab(id, in: source.id, at: date) }
            if let selectedID = source.selectedTabID, selected.contains(selectedID),
                let spaceIndex = spaces.firstIndex(where: { $0.id == source.id })
            {
                spaces[spaceIndex].selectedTabID = fallback
            }
        case .duplicate:
            var copiedGroups: [SplitGroupID: [TabID]] = [:]
            for tab in tabs {
                guard
                    let copy = duplicateTab(
                        tab.id, in: source.id,
                        requestedIndex: space(id: source.id)?.tabs.count, shouldSelect: false, at: date)
                else {
                    throw BrowserTabBatchError.invalidDestination
                }
                result.copies.append((tab.id, copy))
                if let group = source.splitGroup(containing: tab.id) { copiedGroups[group, default: []].append(copy) }
            }
            for copies in copiedGroups.values {
                guard let first = copies.first else { continue }
                for id in copies.dropFirst() {
                    guard addTabToSplit(id, joining: first, at: nil, in: source.id, at: date) else {
                        throw BrowserTabBatchError.invalidDestination
                    }
                }
            }
            if let index = spaces.firstIndex(where: { $0.id == source.id }) {
                spaces[index].selectedTabID = source.selectedTabID
            }
        case .keepLoaded(let value):
            guard tabs.allSatisfy({ $0.nativeContent == nil }) else { throw BrowserTabBatchError.webPagesOnly }
            guard let index = spaces.firstIndex(where: { $0.id == source.id }) else {
                throw BrowserTabBatchError.staleSelection
            }
            for i in spaces[index].tabs.indices where selected.contains(spaces[index].tabs[i].id) {
                spaces[index].tabs[i].keepsPageLoaded = value
            }
        case .separateSplits:
            for group in groupIDs { _ = dissolveSplit(group, in: source.id, at: date) }
        }
        return result
    }

    private mutating func orderBatchMembers(_ ids: [TabID], in spaceID: SpaceID) {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        let selected = Set(ids)
        let byID = Dictionary(uniqueKeysWithValues: spaces[index].tabs.map { ($0.id, $0) })
        var iterator = ids.makeIterator()
        spaces[index].tabs = spaces[index].tabs.map { tab in
            guard selected.contains(tab.id), let id = iterator.next(), let value = byID[id] else { return tab }
            return value
        }
    }
}
