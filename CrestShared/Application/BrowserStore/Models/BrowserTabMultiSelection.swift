import Foundation
import Observation

/// Window-local selection, separate from the tab whose page is active.
@Observable
@MainActor
final class BrowserTabMultiSelection {
    private(set) var selectedItems: Set<BrowserSelectionItemID> = []
    var selectedIDs: Set<TabID> { Set(selectedItems.compactMap(\.tabID)) }
    private(set) var anchorItem: BrowserSelectionItemID?
    var anchorID: TabID? { anchorItem?.tabID }
    private(set) var focusedItem: BrowserSelectionItemID?
    var focusedID: TabID? { focusedItem?.tabID }
    private(set) var isEngaged = false
    var ownsKeyboardFocus = false
    var message: String?
    private(set) var rejectedPinnedIDs: Set<TabID> = []
    private(set) var pinnedRejectionGeneration = 0
    private var rangeBase: Set<BrowserSelectionItemID>?

    func click(
        _ id: BrowserSelectionItemID, units: [[BrowserSelectionItemID]], command: Bool = false, shift: Bool = false
    ) {
        guard let target = units.firstIndex(where: { $0.contains(id) }) else { return }
        focusedItem = units[target].first
        ownsKeyboardFocus = true
        if shift, let anchorItem, let anchor = units.firstIndex(where: { $0.contains(anchorItem) }) {
            if rangeBase == nil { rangeBase = command ? selectedItems : [] }
            let range = Set(units[min(anchor, target)...max(anchor, target)].flatMap { $0 })
            selectedItems = (rangeBase ?? []).union(range)
            isEngaged = true
            return
        }
        rangeBase = nil
        anchorItem = units[target].first
        let unit = Set(units[target])
        if command {
            if unit.isSubset(of: selectedItems) { selectedItems.subtract(unit) } else { selectedItems.formUnion(unit) }
        } else {
            selectedItems = unit
        }
        isEngaged = command || shift
    }

    func selectAll(units: [[BrowserSelectionItemID]]) {
        selectedItems = Set(units.flatMap { $0 })
        anchorItem = units.first?.first
        focusedItem = units.last?.first
        rangeBase = nil
        isEngaged = true
        ownsKeyboardFocus = true
    }

    func selectForKeyboard(_ id: BrowserSelectionItemID, units: [[BrowserSelectionItemID]]) {
        click(id, units: units)
        isEngaged = true
    }

    func reconcile(units: [[BrowserSelectionItemID]]) {
        let available = Set(units.flatMap { $0 })
        selectedItems.formIntersection(available)
        rangeBase = rangeBase.map { $0.intersection(available) }
        if let anchorItem, !available.contains(anchorItem) { self.anchorItem = nil }
        if let focusedItem, !available.contains(focusedItem) { self.focusedItem = nil }
        // A changed group is never partially selected after a live update.
        for unit in units where !selectedItems.isDisjoint(with: unit) {
            if !Set(unit).isSubset(of: selectedItems) { selectedItems.subtract(unit) }
        }
    }

    func clear() {
        selectedItems = []
        anchorItem = nil
        focusedItem = nil
        rangeBase = nil
        isEngaged = false
        ownsKeyboardFocus = false
    }

    func contains(_ id: BrowserSelectionItemID) -> Bool { isEngaged && selectedItems.contains(id) }

    func prepareForDrag(_ request: BrowserTabBatchRequest, in space: BrowserSpace) -> BrowserTabBatchRequest {
        let pins = Set(request.members.filter { $0.placement == .pinned }.map(\.id))
        guard !pins.isEmpty, pins.count < request.ids.count || request.hasFolders else { return request }
        rejectedPinnedIDs = pins
        pinnedRejectionGeneration &+= 1
        selectedItems.subtract(pins.map(BrowserSelectionItemID.tab))
        rangeBase = nil
        let remaining = request.ids.filter { !pins.contains($0) }
        if let anchorID, pins.contains(anchorID) { self.anchorItem = remaining.first.map(BrowserSelectionItemID.tab) }
        if let focusedID, pins.contains(focusedID) {
            self.focusedItem = remaining.first.map(BrowserSelectionItemID.tab)
        }
        return BrowserTabBatchRequest(
            items: request.rootItems.filter { $0.tabID.map(pins.contains) != true }, in: space)
    }
    func contains(_ id: TabID) -> Bool { contains(.tab(id)) }

    func click(_ id: TabID, units: [[BrowserSelectionItemID]], command: Bool = false, shift: Bool = false) {
        click(.tab(id), units: units, command: command, shift: shift)
    }
    func click(_ id: TabID, units: [[TabID]], command: Bool = false, shift: Bool = false) {
        click(.tab(id), units: units.map { $0.map(BrowserSelectionItemID.tab) }, command: command, shift: shift)
    }
    func selectAll(units: [[TabID]]) { selectAll(units: units.map { $0.map(BrowserSelectionItemID.tab) }) }
    func reconcile(units: [[TabID]]) { reconcile(units: units.map { $0.map(BrowserSelectionItemID.tab) }) }
    func selectForKeyboard(_ id: TabID, units: [[TabID]]) {
        selectForKeyboard(.tab(id), units: units.map { $0.map(BrowserSelectionItemID.tab) })
    }

}
