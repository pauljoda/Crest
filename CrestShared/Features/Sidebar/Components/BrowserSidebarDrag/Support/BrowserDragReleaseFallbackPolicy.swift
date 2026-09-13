enum BrowserDragReleaseFallbackPolicy {
    /// Clears a provider or drag session that never receives native completion.
    static let sessionExpiration: Duration = .seconds(30)

    /// Give a destination's synchronous `performDrop` callback time to finish
    /// before treating the touch release as a cancelled/outside drop.
    static let cleanupDelay: Duration = .milliseconds(180)
}
