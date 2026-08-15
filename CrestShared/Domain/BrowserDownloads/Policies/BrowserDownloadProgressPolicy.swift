enum BrowserDownloadProgressPolicy {
    static let minimumPublishedDelta = 0.01

    static func normalized(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    static func shouldPublish(previous: Double, next: Double) -> Bool {
        let previous = normalized(previous)
        let next = normalized(next)
        return next == 0
            || next == 1
            || abs(next - previous) >= minimumPublishedDelta
    }
}
