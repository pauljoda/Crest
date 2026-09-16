import Foundation

@MainActor
enum BrowserSidebarSelection {
    /// Logical row order survives lazy view removal. Pointer targeting still
    /// uses the platform's live view bounds independently of this projection.
    static func logicalItems(
        in space: BrowserSpace, keptTabID: (FolderID) -> TabID?
    ) -> [BrowserSelectionItemID] {
        let sections = space.tabSections
        let tree = space.folderTree
        var result = sections.pinnedTabs.filter { !$0.isStartPage }.map { BrowserSelectionItemID.tab($0.id) }

        func append(_ items: [BrowserSidebarFolderListItem], from projection: BrowserSidebarFolderListItem.Projection) {
            for item in items {
                switch item {
                case .tabs(let row):
                    result.append(contentsOf: row.tabs.filter { !$0.isStartPage }.map { .tab($0.id) })
                case .folder(let node):
                    result.append(.folder(node.id))
                    if !node.folder.isCollapsed {
                        append(projection.items(in: node.id), from: projection)
                    } else if let id = keptTabID(node.id),
                        let row = BrowserSidebarTabListItemPolicy.collapsedItem(
                            keeping: id, in: sections.tabs(in: node.id))
                    {
                        result.append(contentsOf: row.tabs.filter { !$0.isStartPage }.map { .tab($0.id) })
                    }
                }
            }
        }

        if space.isSavedTabsExpanded {
            let saved = BrowserSidebarFolderListItem.Projection(tabs: space.tabs, tree: tree, location: .saved)
            append(saved.items(), from: saved)
        }
        let current = BrowserSidebarFolderListItem.Projection(
            tabs: sections.sidebarCurrentTabs, tree: tree, location: .current)
        append(current.items(), from: current)
        return result
    }

    static func units(in browser: BrowserStore, reorder: BrowserSidebarReorderState) -> [[TabID]] {
        itemUnits(in: browser, reorder: reorder).map { $0.compactMap(\.tabID) }.filter { !$0.isEmpty }
    }

    static func itemUnits(in browser: BrowserStore, reorder: BrowserSidebarReorderState) -> [[BrowserSelectionItemID]] {
        guard let space = browser.selectedSpace else { return [] }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let items =
            BrowserPlatformSidebarSelectionOrder.orderedItems(in: browser, assignment: assignment)
            ?? registeredItems(in: browser, assignment: assignment, reorder: reorder)
        let tabsByID = Dictionary(uniqueKeysWithValues: space.tabs.map { ($0.id, $0) })
        let folderIDs = Set(space.folders.map(\.id))
        var included: Set<BrowserSelectionItemID> = []
        return items.compactMap { item in
            guard !included.contains(item) else { return nil }
            let unit: [BrowserSelectionItemID]
            switch item {
            case .folder(let id):
                guard folderIDs.contains(id) else { return nil }
                unit = [item]
            case .tab(let id):
                guard let tab = tabsByID[id], !tab.isStartPage else { return nil }
                unit = tab.splitGroupID.map { space.splitGroupMembers(of: $0).map { .tab($0.id) } } ?? [item]
            }
            included.formUnion(unit)
            return unit
        }
    }

    private static func registeredItems(
        in browser: BrowserStore, assignment: BrowserSpaceRuntimeAssignment, reorder: BrowserSidebarReorderState
    )
        -> [BrowserSelectionItemID]
    {
        reorder.selectionRows(in: assignment).compactMap {
            switch $0.id {
            case .tab(let id): .tab(id)
            case .folder(let id): .folder(id)
            case .splitGroup(let id): browser.selectedSpace?.splitGroupMembers(of: id).first.map { .tab($0.id) }
            }
        }
    }

    static func isCoveredBySelectedFolder(_ item: BrowserSelectionItemID, in browser: BrowserStore) -> Bool {
        guard let space = browser.selectedSpace, browser.tabMultiSelection.isEngaged else { return false }
        var parent: FolderID?
        switch item {
        case .tab(let id): parent = space.tabs.first { $0.id == id }?.folderID
        case .folder(let id): parent = space.folders.first { $0.id == id }?.parentID
        }
        var visited: Set<FolderID> = []
        while let id = parent, visited.insert(id).inserted {
            if browser.tabMultiSelection.contains(.folder(id)) { return true }
            parent = space.folders.first { $0.id == id }?.parentID
        }
        return false
    }

    static func request(for id: TabID, browser: BrowserStore, reorder: BrowserSidebarReorderState)
        -> BrowserTabBatchRequest?
    {
        request(for: .tab(id), browser: browser, reorder: reorder)
    }

    static func request(for item: BrowserSelectionItemID, browser: BrowserStore, reorder: BrowserSidebarReorderState)
        -> BrowserTabBatchRequest?
    {
        let selection = browser.tabMultiSelection
        guard selection.contains(item), let space = browser.selectedSpace else { return nil }
        let items = itemUnits(in: browser, reorder: reorder).flatMap { $0 }.filter {
            selection.selectedItems.contains($0)
        }
        guard items.contains(item) else { return nil }
        return BrowserTabBatchRequest(items: items, in: space)
    }
}
