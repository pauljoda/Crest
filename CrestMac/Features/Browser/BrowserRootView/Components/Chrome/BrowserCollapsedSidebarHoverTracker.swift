import SwiftUI

/// Adds the Mac window server's pointer tracking to the shared collapsed-edge
/// reveal control without taking any input away from the page underneath it.
/// It spans the window, with the strip `stripWidth` wide along `edge`.
struct BrowserCollapsedSidebarHoverTracker: NSViewRepresentable {
    let stripWidth: CGFloat
    let edge: HorizontalEdge
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    func makeNSView(
        context: Context
    ) -> BrowserCollapsedSidebarHoverTrackingView {
        BrowserCollapsedSidebarHoverTrackingView(
            onHoverChange: onHoverChange
        )
    }

    func updateNSView(
        _ nsView: BrowserCollapsedSidebarHoverTrackingView,
        context: Context
    ) {
        nsView.onHoverChange = onHoverChange
        nsView.setStrip(width: stripWidth, along: stripRectEdge(in: context.environment.layoutDirection))
    }

    /// AppKit keeps its coordinates left to right whatever the layout
    /// direction, so a leading or trailing edge is resolved to a side here.
    private func stripRectEdge(in layoutDirection: LayoutDirection) -> CGRectEdge {
        (edge == .leading) == (layoutDirection == .leftToRight) ? .minXEdge : .maxXEdge
    }
}
