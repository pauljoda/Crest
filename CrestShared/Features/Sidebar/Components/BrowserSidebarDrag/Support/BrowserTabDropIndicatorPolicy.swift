enum BrowserTabDropIndicatorPolicy {
    @MainActor
    static func isVisible(
        at location: BrowserTabDropLocation,
        dragState: BrowserTabDragState
    ) -> Bool {
        location.placement != .pinned
            && dragState.item != nil
            && dragState.dropLocation == location
    }
}
