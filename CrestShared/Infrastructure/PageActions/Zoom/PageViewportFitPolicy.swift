import CoreGraphics

/// Presentation-only fitting does not change the person's requested page zoom.
enum BrowserPageViewportFitPolicy {
    static func zoom(requested: CGFloat, viewportWidth: CGFloat, minimumContentWidth: CGFloat) -> CGFloat {
        guard requested.isFinite, requested > 0, viewportWidth.isFinite, viewportWidth > 0,
            minimumContentWidth.isFinite, minimumContentWidth > 0
        else { return requested }
        // Keep the browser's normal readability floor in extremely narrow cards.
        return min(requested, max(BrowserPageZoomPolicy.levels[0], viewportWidth / minimumContentWidth))
    }
}
