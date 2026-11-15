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
/// Inside the window, the pointer also has to stay on the strip a moment before
/// the sidebar comes out, for as long as Appearance's Sidebar hover delay asks.
/// A pointer passing over the edge on its way to something near it, a control
/// at the side of the page, never brings the sidebar out; with no delay, any
/// pointer reaching the strip does.
///
/// A pointer that leaves the window through the edge on the sidebar's side
/// brings the sidebar out at once, without the delay, however fast it went:
/// reaching for the edge of a window that stands away from the screen's edge
/// often carries it across the strip and out, even so fast that AppKit never
/// saw it on the strip, and the window's own exit reveals it then.
@MainActor
final class BrowserCollapsedSidebarHoverTrackingView: NSView {
    // MARK: - Variables

    var onHoverChange: @MainActor @Sendable (Bool) -> Void

    private let pointerLocation: @MainActor () -> NSPoint
    private var trackingArea: NSTrackingArea?
    /// Covers the window's content, so a pointer leaving the window reports
    /// it wherever it last was.
    private var windowTrackingArea: NSTrackingArea?
    /// Where the pointer rested when the strip appeared, until it moves.
    private var restingPointer: NSPoint?
    /// The reveal waiting for the pointer to stay on the strip.
    private var pendingReveal: Task<Void, Never>?

    /// Whether the pointer is on the strip in the key window.
    private var isPointerOnStrip: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return false }
        return bounds.contains(convert(window.convertPoint(fromScreen: pointerLocation()), from: nil))
    }

    /// Whether the pointer is out of the key window past the edge the strip
    /// lies along.
    private var isPointerPastStrip: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor, let content = window.contentView else {
            return false
        }
        let strip = convert(bounds, to: nil)
        let location = window.convertPoint(fromScreen: pointerLocation())
        let edges = content.bounds
        // The strip lies along the window's edge on the sidebar's side.
        return strip.midX < edges.midX ? location.x < edges.minX : location.x > edges.maxX
    }

    /// Whether the pointer rests on the strip, or is out past the window's
    /// edge beside it.
    private var isPointerReachingForStrip: Bool {
        isPointerOnStrip || isPointerPastStrip
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
        // The window area spans the window the view just joined.
        if window != nil { updateTrackingAreas() }
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
        if let windowTrackingArea {
            removeTrackingArea(windowTrackingArea)
            self.windowTrackingArea = nil
        }
        guard let content = window?.contentView else { return }
        let windowArea = NSTrackingArea(
            rect: convert(content.bounds, from: content),
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(windowArea)
        windowTrackingArea = windowArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea !== windowTrackingArea else { return }
        revealIfPointerMoved()
    }

    override func mouseMoved(with event: NSEvent) {
        revealIfPointerMoved()
    }

    override func mouseExited(with event: NSEvent) {
        let isPastStrip = isPointerPastStrip
        // The window's own exit counts only through the strip's edge, where a
        // pointer too fast for the strip to see crossed it on the way.
        if event.trackingArea === windowTrackingArea, !isPastStrip { return }
        restingPointer = nil
        cancelPendingReveal()
        // Out through the window's edge, the pointer was reaching for the
        // sidebar, which comes out at once.
        reportHover(isPastStrip)
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
            if isPointerReachingForStrip { reportHover(true) }
            return
        }
        pendingReveal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            pendingReveal = nil
            guard isPointerReachingForStrip else { return }
            reportHover(true)
        }
    }

    private func cancelPendingReveal() {
        pendingReveal?.cancel()
        pendingReveal = nil
    }
}
