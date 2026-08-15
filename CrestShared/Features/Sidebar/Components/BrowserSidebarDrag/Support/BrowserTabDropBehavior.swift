enum BrowserTabDropBehavior {
    static func accepts(
        item: BrowserTabDragItem,
        at location: BrowserTabDropLocation
    ) -> Bool {
        true
    }

    static func shouldMove(
        item: BrowserTabDragItem,
        at location: BrowserTabDropLocation
    ) -> Bool {
        guard item.tabID == location.beforeTabID else { return true }
        guard let destination = location.destinationAssignment else {
            return false
        }
        return item.spaceAssignment != destination
    }

    static func performsLiveMove(at location: BrowserTabDropLocation) -> Bool {
        location.placement == .pinned
    }
}
