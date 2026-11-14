import AppKit

/// A transparent leading-edge view whose hover events come from AppKit.
///
/// SwiftUI's `.onHover` can miss the transition when the view behind the edge
/// is a live `WKWebView`. `NSTrackingArea` observes the window-level pointer
/// crossing instead, while `hitTest` keeps clicks, scrolling, and page drags
/// owned by the shared reveal button and the web content beneath it.
///
/// The strip reveals only for a pointer that moves onto it. One already resting
/// where the strip appears, as the sidebar it just hid slides away, has not
/// reached for the edge again: Universal Control leaves the pointer parked
/// there after crossing to another Mac.
///
/// The pointer also has to stay on the strip a moment before the sidebar comes
/// out, for as long as Appearance's Sidebar hover delay asks. A pointer passing
/// over the edge on its way to something near it, a control at the side of the
/// page, never brings the sidebar out; with no delay, any pointer reaching the
/// strip does.
@MainActor
final class BrowserCollapsedSidebarHoverTrackingView: NSView {
    // MARK: - Variables

    var onHoverChange: @MainActor @Sendable (Bool) -> Void

    private let pointerLocation: @MainActor () -> NSPoint
    private var trackingArea: NSTrackingArea?
    /// Where the pointer rested when the strip appeared, until it moves.
    private var restingPointer: NSPoint?
    /// The reveal waiting for the pointer to stay on the strip.
    private var pendingReveal: Task<Void, Never>?

    /// Whether the pointer is on the strip in the key window.
    private var isPointerOnStrip: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return false }
        return bounds.contains(convert(window.convertPoint(fromScreen: pointerLocation()), from: nil))
    }

    /// How long the pointer stays on the strip before the sidebar comes out,
    /// as Appearance sets it.
    private var revealDelay: Duration {
        SidebarRevealDelayPreference.delay(BrowserDeviceAppearanceStore.shared.sidebarRevealDelay)
    }

    // MARK: - Initializers

    init(
        pointerLocation: @escaping @MainActor () -> NSPoint = { NSEvent.mouseLocation },
        onHoverChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.pointerLocation = pointerLocation
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions - Hover

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelPendingReveal()
        restingPointer = window == nil ? nil : pointerLocation()
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
                .mouseMoved,
                .activeInKeyWindow,
                .inVisibleRect,
            ],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        revealIfPointerMoved()
    }

    override func mouseMoved(with event: NSEvent) {
        revealIfPointerMoved()
    }

    override func mouseExited(with event: NSEvent) {
        restingPointer = nil
        cancelPendingReveal()
        reportHover(false)
    }

    func reportHover(_ isHovering: Bool) {
        onHoverChange(isHovering)
    }

    /// Starts the wait for a pointer that moved onto the strip, or reveals at
    /// once without one. Moving along the strip keeps the wait going; leaving
    /// it ends the wait.
    private func revealIfPointerMoved() {
        if let restingPointer {
            guard pointerLocation() != restingPointer else { return }
            self.restingPointer = nil
        }
        guard pendingReveal == nil else { return }
        let delay = revealDelay
        guard delay > .zero else {
            if isPointerOnStrip { reportHover(true) }
            return
        }
        pendingReveal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            pendingReveal = nil
            guard isPointerOnStrip else { return }
            reportHover(true)
        }
    }

    private func cancelPendingReveal() {
        pendingReveal?.cancel()
        pendingReveal = nil
    }
}
