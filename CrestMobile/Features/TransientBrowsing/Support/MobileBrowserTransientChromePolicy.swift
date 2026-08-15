enum MobileBrowserTransientChromePolicy {
    /// Peek and Quick Window retain their WebKit back-forward lists, but their
    /// intentionally compact chrome exposes only dismissal and promotion.
    static let rendersHistoryControls = false
}
