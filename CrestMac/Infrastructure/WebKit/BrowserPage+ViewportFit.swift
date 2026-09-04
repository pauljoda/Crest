import AppKit
import WebKit

extension BrowserPage {
    func fitViewport(width: CGFloat, owner: UUID) async {
        guard width.isFinite, width > 0 else { return }
        viewportFitOwner = owner
        viewportFitGeneration &+= 1
        let generation = viewportFitGeneration
        let requestedZoom = pageZoom
        // Only an authored minimum width triggers fitting. Tables, carousels,
        // and other intentionally scrollable content keep their own behavior.
        let value = try? await webView.callAsyncJavaScript(
            """
            return Math.max(0, ...[document.documentElement, document.body].filter(Boolean).map(element => {
                const value = parseFloat(getComputedStyle(element).minWidth);
                return Number.isFinite(value) ? value : 0;
            }));
            """, arguments: [:], contentWorld: .defaultClient
        )
        guard !Task.isCancelled, viewportFitOwner == owner, viewportFitGeneration == generation,
            pageZoom == requestedZoom, let minimum = value as? Double
        else { return }
        webView.pageZoom = BrowserPageViewportFitPolicy.zoom(
            requested: requestedZoom, viewportWidth: width, minimumContentWidth: CGFloat(minimum)
        )
    }

    func releaseViewportFit(owner: UUID) {
        guard viewportFitOwner == owner else { return }
        viewportFitOwner = nil
        viewportFitGeneration &+= 1
        webView.pageZoom = pageZoom
    }
}
