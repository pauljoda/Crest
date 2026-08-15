import CoreGraphics

/// Lift treatment for a sidebar reorder — the row rises off the list under the
/// pointer, the way a home-screen icon does.
enum BrowserSidebarReorderVisuals {
    /// How far the preview rises. Applied where the preview is drawn, which is
    /// the window-level host rather than the row: the row stands down for the
    /// whole lift. Every drag preview carries its own drop shadow, so the rise
    /// is all that is left to say here.
    static let liftScale: CGFloat = 1.04

    /// A lifted row travels outside the scrolling region — into the pinned grid
    /// above, for instance — so the scroll clip has to be lifted for the
    /// duration of the drag or the row is clipped away mid-gesture.
    static func clipsScrollableRegion(
        clipsWhenIdle: Bool,
        isDragging: Bool
    ) -> Bool {
        clipsWhenIdle && !isDragging
    }
}
