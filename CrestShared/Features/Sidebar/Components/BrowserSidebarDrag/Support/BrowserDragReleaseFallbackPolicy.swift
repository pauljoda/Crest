enum BrowserDragReleaseFallbackPolicy {
    /// Give a destination's synchronous `performDrop` callback time to finish
    /// before treating the touch release as a cancelled/outside drop.
    static let cleanupDelay: Duration = .milliseconds(180)
}
