enum BrowserPlatformTabDropExitPolicy {
    @MainActor
    static func handleExit(
        resetsPreviewOnExit: Bool,
        dragState: BrowserTabDragState,
        owns: (BrowserTabDropLocation) -> Bool
    ) {
        if resetsPreviewOnExit {
            dragState.leavePinnedZone()
        } else if let activeLocation = dragState.dropLocation,
            owns(activeLocation)
        {
            dragState.leave(activeLocation)
        }
    }
}
