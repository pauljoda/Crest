enum BrowserTabDropIndicatorPolicy {
    @MainActor
    static func isVisible(
        at location: BrowserTabDropLocation,
        dragState: BrowserTabDragState
    ) -> Bool {
        !location.placement.isGrid
            && dragState.item != nil
            && dragState.dropLocation == location
    }
}
