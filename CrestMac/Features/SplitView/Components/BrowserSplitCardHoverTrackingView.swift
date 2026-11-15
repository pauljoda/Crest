import AppKit

/// A transparent view that reports where the pointer is while it is inside its
/// bounds: as it arrives, and as it moves.
///
/// SwiftUI's `.onHover` is not usable here: a card's content is a `WKWebView`, and
/// hover callbacks over live web content arrive late, arrive once, or do not
/// arrive at all depending on what the page does with the pointer. An
/// `NSTrackingArea` is answered by AppKit's own tracking machinery instead of by
/// the view under the cursor, so it reports the truth regardless of the page.
///
/// The view is inert in every other respect. `hitTest` returns `nil`, so it can
/// sit above live web content — where tracking is most reliable — without taking
/// a single click, scroll, or drag away from the page beneath it.
///
/// `.inVisibleRect` means the tracked region follows the view's visible bounds,
/// so a card that resizes, scrolls, or is clipped by a narrowing window needs no
/// rebuild of its own. `.activeInKeyWindow` keeps a background window from moving
/// focus in the window someone is actually working in.
///
/// A tracking area answers to geometry alone, so it reports the pointer entering
/// a card even while chrome drawn over the card, such as a Peek, is what the
/// pointer is on. A pointer that then moves off that chrome onto the card never
/// enters again, so that one move is reported too. Other moves are not, so focus
/// moved from the keyboard stays until the pointer next arrives. The view is
/// flipped, so a location reads from the top, as the SwiftUI frames it is
/// compared with do.
@MainActor
final class BrowserSplitCardHoverTrackingView: NSView {
    /// Told the pointer's location in this view's bounds as it arrives.
    var onPointerInside: @MainActor @Sendable (CGPoint) -> Void
    /// Whether chrome drawn over the card covers a location in its bounds.
    var isCovered: @MainActor @Sendable (CGPoint) -> Bool

    private var trackingArea: NSTrackingArea?
    /// Whether the pointer was last on chrome drawn over the card.
    private var wasCovered = false

    init(
        isCovered: @escaping @MainActor @Sendable (CGPoint) -> Bool,
        onPointerInside: @escaping @MainActor @Sendable (CGPoint) -> Void
    ) {
        self.isCovered = isCovered
        self.onPointerInside = onPointerInside
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            // `.inVisibleRect` supplies the rect, so this one is ignored.
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        wasCovered = isCovered(location)
        onPointerInside(location)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let covered = isCovered(location)
        defer { wasCovered = covered }
        guard wasCovered, !covered else { return }
        onPointerInside(location)
    }

    /// Leaving the card is this view's own tracking, which nothing beneath it
    /// should hear.
    override func mouseExited(with event: NSEvent) {}
}
