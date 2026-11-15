import AppKit

/// A transparent view over the window whose hover events come from AppKit,
/// with the reveal strip along its edge on the sidebar's side.
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
/// A pointer that leaves the window through its edge on the sidebar's side
/// brings the sidebar out at once, without the delay, however fast it went or
/// far it goes. AppKit keeps a view's tracking to the view itself, so the view
/// spans the window to see every exit, wherever the pointer last was; a fast
/// move can skip the strip altogether. Where the pointer crossed the window's
/// edge, between where it was last seen inside and where it is now, decides.
@MainActor
final class BrowserCollapsedSidebarHoverTrackingView: NSView {
    // MARK: - Static Variables

    /// How far above or below the window a pointer may cross the line of its
    /// sidebar edge and still count as leaving through that edge.
    static let edgeSlack: CGFloat = 24

    // MARK: - Variables

    var onHoverChange: @MainActor @Sendable (Bool) -> Void

    private let pointerLocation: @MainActor () -> NSPoint
    /// Covers the strip.
    private var stripTrackingArea: NSTrackingArea?
    /// Covers the window's content, so a pointer leaving the window reports
    /// it wherever it last was, and follows the pointer inside.
    private var windowTrackingArea: NSTrackingArea?
    private var stripWidth: CGFloat = 0
    /// The view's edge the strip lies along: the window's edge on the
    /// sidebar's side.
    private var stripEdge: CGRectEdge = .minXEdge
    /// Where the pointer was last seen in the window, on screen.
    private var lastInside: NSPoint?
    /// Where the pointer rested when the strip appeared, until it moves.
    private var restingPointer: NSPoint?
    /// The reveal waiting for the pointer to stay on the strip.
    private var pendingReveal: Task<Void, Never>?

    private var stripRect: NSRect {
        bounds.divided(atDistance: stripWidth, from: stripEdge).slice
    }

    /// Whether the pointer is on the strip in the key window.
    private var isPointerOnStrip: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return false }
        return stripRect.contains(convert(window.convertPoint(fromScreen: pointerLocation()), from: nil))
    }

    /// Whether the pointer is out of the key window past its edge on the
    /// sidebar's side, beside the window give or take ``edgeSlack``.
    private var isPointerPastStrip: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return false }
        let frame = window.frame
        let location = pointerLocation()
        guard location.y >= frame.minY - Self.edgeSlack, location.y <= frame.maxY + Self.edgeSlack else { return false }
        return stripEdge == .minXEdge ? location.x < frame.minX : location.x > frame.maxX
    }

    /// Whether the pointer, now out of the key window, crossed its edge on the
    /// sidebar's side on the way out: the line from where it was last seen
    /// inside to where it is now meets that edge beside the window, give or
    /// take ``edgeSlack``.
    private var hasPointerLeftThroughStripEdge: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return false }
        let frame = window.frame
        let end = pointerLocation()
        let edge = stripEdge == .minXEdge ? frame.minX : frame.maxX
        guard stripEdge == .minXEdge ? end.x < edge : end.x > edge else { return false }
        let start = lastInside ?? end
        let crossing = start.x == end.x ? end.y : start.y + (edge - start.x) / (end.x - start.x) * (end.y - start.y)
        return crossing >= frame.minY - Self.edgeSlack && crossing <= frame.maxY + Self.edgeSlack
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
        lastInside = nil
        restingPointer = window == nil ? nil : pointerLocation()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in [stripTrackingArea, windowTrackingArea].compactMap(\.self) {
            removeTrackingArea(area)
        }
        let strip = NSTrackingArea(
            rect: stripRect, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        let window = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(strip)
        addTrackingArea(window)
        stripTrackingArea = strip
        windowTrackingArea = window
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === stripTrackingArea else {
            lastInside = pointerLocation()
            return
        }
        revealIfPointerMoved()
    }

    override func mouseMoved(with event: NSEvent) {
        lastInside = pointerLocation()
        if isPointerOnStrip { revealIfPointerMoved() }
    }

    override func mouseExited(with event: NSEvent) {
        // Out of the window through its edge on the sidebar's side, the
        // pointer was reaching for the sidebar, which comes out at once.
        let isLeaving = event.trackingArea === windowTrackingArea
        let reachedForSidebar = isLeaving ? hasPointerLeftThroughStripEdge : isPointerPastStrip
        if isLeaving { lastInside = nil }
        guard reachedForSidebar || !isLeaving else { return }
        restingPointer = nil
        cancelPendingReveal()
        reportHover(reachedForSidebar)
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

    // MARK: - Mutators

    /// Sets the strip's width and the view's edge it lies along.
    func setStrip(width: CGFloat, along edge: CGRectEdge) {
        guard width != stripWidth || edge != stripEdge else { return }
        stripWidth = width
        stripEdge = edge
        updateTrackingAreas()
    }
}
