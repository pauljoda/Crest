import Foundation

@MainActor
enum BrowserSidebarSelection {
    static func units(in browser: BrowserStore) -> [[TabID]] {
        itemUnits(in: browser).map { $0.compactMap(\.tabID) }.filter { !$0.isEmpty }
    }

    static func itemUnits(in browser: BrowserStore) -> [[BrowserSelectionItemID]] {
        guard let space = browser.selectedSpace else { return [] }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let items: [BrowserSelectionItemID]
        #if os(macOS)
            items =
                BrowserNativeTabSelectionTarget.TargetView.orderedItems(browser: browser, assignment: assignment)
                ?? registeredItems(in: browser, assignment: assignment)
        #else
            items = registeredItems(in: browser, assignment: assignment)
        #endif
        var included: Set<BrowserSelectionItemID> = []
        return items.compactMap { item in
            guard !included.contains(item) else { return nil }
            let unit: [BrowserSelectionItemID]
            switch item {
            case .folder(let id):
                guard space.folders.contains(where: { $0.id == id }) else { return nil }
                unit = [item]
            case .tab(let id):
                guard let tab = space.tabs.first(where: { $0.id == id }), !tab.isStartPage else { return nil }
                unit = tab.splitGroupID.map { space.splitGroupMembers(of: $0).map { .tab($0.id) } } ?? [item]
            }
            included.formUnion(unit)
            return unit
        }
    }

    private static func registeredItems(in browser: BrowserStore, assignment: BrowserSpaceRuntimeAssignment)
        -> [BrowserSelectionItemID]
    {
        browser.sidebarReorderState.selectionRows(in: assignment).compactMap {
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

    static func request(for id: TabID, browser: BrowserStore) -> BrowserTabBatchRequest? {
        request(for: .tab(id), browser: browser)
    }

    static func request(for item: BrowserSelectionItemID, browser: BrowserStore) -> BrowserTabBatchRequest? {
        let selection = browser.tabMultiSelection
        guard selection.contains(item), let space = browser.selectedSpace else { return nil }
        let items = itemUnits(in: browser).flatMap { $0 }.filter { selection.selectedItems.contains($0) }
        guard items.contains(item) else { return nil }
        return BrowserTabBatchRequest(items: items, in: space)
    }
}
