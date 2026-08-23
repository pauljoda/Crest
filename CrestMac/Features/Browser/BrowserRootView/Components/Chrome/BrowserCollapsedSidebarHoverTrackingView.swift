import AppKit

/// A transparent leading-edge view whose hover events come from AppKit.
///
/// SwiftUI's `.onHover` can miss the transition when the view behind the edge
/// is a live `WKWebView`. `NSTrackingArea` observes the window-level pointer
/// crossing instead, while `hitTest` keeps clicks, scrolling, and page drags
/// owned by the shared reveal button and the web content beneath it.
@MainActor
final class BrowserCollapsedSidebarHoverTrackingView: NSView {
    var onHoverChange: @MainActor @Sendable (Bool) -> Void

    private var trackingArea: NSTrackingArea?

    init(onHoverChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect,
            ],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        reportHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        reportHover(false)
    }

    func reportHover(_ isHovering: Bool) {
        onHoverChange(isHovering)
    }
}
