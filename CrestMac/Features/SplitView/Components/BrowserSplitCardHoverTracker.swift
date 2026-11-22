import SwiftUI

/// Attaches AppKit hover tracking to one Split View card.
///
/// Placed as an overlay so the tracked region is the card's full bounds — web
/// content, find bar, failure overlay and all — and reports nothing but where
/// the pointer is inside this card. What that is worth is decided by
/// `BrowserSplitPageSurface.focusesOnHover`, not here.
struct BrowserSplitCardHoverTracker: NSViewRepresentable {
    let isCovered: @MainActor @Sendable (CGPoint) -> Bool
    let onPointerInside: @MainActor @Sendable (CGPoint) -> Void

    func makeNSView(context: Context) -> BrowserSplitCardHoverTrackingView {
        BrowserSplitCardHoverTrackingView(isCovered: isCovered, onPointerInside: onPointerInside)
    }

    func updateNSView(
        _ nsView: BrowserSplitCardHoverTrackingView,
        context: Context
    ) {
        nsView.isCovered = isCovered
        nsView.onPointerInside = onPointerInside
    }
}
