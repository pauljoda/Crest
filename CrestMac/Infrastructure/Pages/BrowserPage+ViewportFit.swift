import AppKit

extension BrowserPage {
    // Only an authored minimum width triggers fitting. Tables, carousels, and
    // other intentionally scrollable content keep their own behavior.
    private static let authoredMinimumWidthScript = """
        return Math.max(0, ...[document.documentElement, document.body].filter(Boolean).map(element => {
            const value = parseFloat(getComputedStyle(element).minWidth);
            return Number.isFinite(value) ? value : 0;
        }));
        """

    func fitViewport(width: CGFloat, owner: UUID) async {
        guard width.isFinite, width > 0, developerViewport == nil else { return }
        viewportFitOwner = owner
        viewportFitGeneration &+= 1
        let generation = viewportFitGeneration
        let requestedZoom = pageZoom
        let value = await pageEngine.evaluateInMainFrame(Self.authoredMinimumWidthScript)
        guard !Task.isCancelled, viewportFitOwner == owner, viewportFitGeneration == generation,
            pageZoom == requestedZoom, developerViewport == nil, let minimum = (value as? NSNumber)?.doubleValue
        else { return }
        let zoom = BrowserPageViewportFitPolicy.zoom(
            requested: requestedZoom, viewportWidth: width, minimumContentWidth: CGFloat(minimum)
        )
        pageEngine.setZoom(zoom)
    }

    func releaseViewportFit(owner: UUID) {
        guard viewportFitOwner == owner else { return }
        viewportFitOwner = nil
        viewportFitGeneration &+= 1
        pageEngine.setZoom(renderedPageZoom)
    }
}
