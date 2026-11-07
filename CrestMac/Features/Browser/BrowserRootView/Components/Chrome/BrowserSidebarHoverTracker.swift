import SwiftUI

struct BrowserSidebarHoverTracker: NSViewRepresentable {
    // MARK: - Variables

    var isRevealedByPointer = false
    /// Whether the sidebar's edge is being dragged to resize it.
    var isResizing = false
    /// How much of the tracker, along `exitEdge`, lies over the page beside
    /// the sidebar rather than over the sidebar itself.
    var exitMargin: CGFloat = 0
    var exitEdge: HorizontalEdge = .trailing
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    // MARK: - Actions - Representation

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        BrowserSidebarHoverTrackingView(onHoverChange: onHoverChange)
    }

    func updateNSView(_ view: BrowserSidebarHoverTrackingView, context: Context) {
        view.onHoverChange = onHoverChange
        view.isRevealedByPointer = isRevealedByPointer
        view.isResizing = isResizing
        view.setExitMargin(exitMargin, on: exitRectEdge(in: context.environment.layoutDirection))
        view.schedulePointerRefresh()
    }

    /// AppKit keeps its coordinates left to right whatever the layout
    /// direction, so a leading or trailing edge is resolved to a side here.
    private func exitRectEdge(in layoutDirection: LayoutDirection) -> CGRectEdge {
        (exitEdge == .trailing) == (layoutDirection == .leftToRight) ? .maxXEdge : .minXEdge
    }
}
