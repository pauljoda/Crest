import AppKit

/// Owns hover across the sidebar's full region, including its leading inset.
///
/// Hover is the pointer resting on the region, held open for as long as
/// something the sidebar opened is still in use: a menu started inside it, a
/// popover or sheet it presented, an extension popup that took the keyboard
/// from its window, or a field of its own being typed into. A hold only keeps a
/// hover the pointer started; it never reveals the sidebar on its own.
///
/// Menu tracking can leave an exit queued after the pointer has returned to
/// the sidebar. Sample the current position instead of trusting that event.
@MainActor
final class BrowserSidebarHoverTrackingView: NSView {
    // MARK: - Static Variables

    /// How long the region stays held after its last hold lets go. A menu item
    /// or a popover often opens its successor — a popover, a sheet, a rename
    /// field — a moment after it closes, and the sidebar that anchors it
    /// should still be there when it arrives.
    static let holdReleaseDelay: TimeInterval = 0.15
    /// How often a pointer resting at the screen edge is sampled while
    /// `edgeRestHideDelay` is set.
    static let edgeRestCheckInterval: TimeInterval = 0.25

    // MARK: - Variables

    var onHoverChange: @MainActor @Sendable (Bool) -> Void
    /// Whether the pointer brought the sidebar out by reaching the window
    /// edge, so it was already on its way in before the region slid under it.
    ///
    /// Each such reveal starts a new hover. The pointer can touch the edge
    /// again while the sidebar it just left is still sliding away, and the
    /// same region comes back with the exit it already reported; leaving
    /// again would repeat that report and never reach the sidebar.
    var isRevealedByPointer = false {
        didSet {
            guard isRevealedByPointer, !oldValue else { return }
            lastReportedHover = nil
        }
    }
    /// How long the pointer may rest motionless at the screen edge before it
    /// counts as gone, or zero to wait for it to move.
    ///
    /// Universal Control leaves this Mac's pointer parked at the screen edge
    /// when it crosses to another Mac, over a sidebar it revealed there, and
    /// reports nothing else until a click on the other Mac moves focus.
    var edgeRestHideDelay: TimeInterval = 0 {
        didSet {
            guard edgeRestHideDelay != oldValue else { return }
            scheduleEdgeRestCheck()
        }
    }

    private let notificationCenter: NotificationCenter
    private let pointerLocation: @MainActor () -> NSPoint
    private let heldPopovers = NSHashTable<NSPopover>.weakObjects()
    private let heldWindows = NSHashTable<NSWindow>.weakObjects()
    private var trackingArea: NSTrackingArea?
    private var firstResponderObservation: NSKeyValueObservation?
    private var trackingMenus: Set<ObjectIdentifier> = []
    private var holdReleaseRevision = 0
    private var isReleasingHold = false
    private var lastReportedHover: Bool?
    private var edgeRestRevision = 0
    private var edgeRest: (point: NSPoint, since: Date)?

    private var isPointerInside: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return false }
        let location = convert(window.convertPoint(fromScreen: pointerLocation()), from: nil)
        return trackedRect.contains(location)
    }

    /// Whether the pointer that revealed the sidebar has gone somewhere a
    /// slide-in cannot explain: out of the window, or into another app. It
    /// can get there before the region first reports it inside, and nothing
    /// in the region reports an exit it never saw an entry for.
    private var hasRevealingPointerLeft: Bool {
        guard isRevealedByPointer, let window else { return false }
        return !window.isKeyWindow || !window.frame.contains(pointerLocation())
    }

    /// Whether the pointer has rested motionless at the edge of its screen for
    /// longer than `edgeRestHideDelay`.
    private var hasPointerRestedAtScreenEdge: Bool {
        guard edgeRestHideDelay > 0, let edgeRest else { return false }
        return Date().timeIntervalSince(edgeRest.since) >= edgeRestHideDelay
    }

    private var isHeldOpen: Bool {
        !trackingMenus.isEmpty
            || !heldPopovers.allObjects.isEmpty
            || !heldWindows.allObjects.isEmpty
            || isReleasingHold
            || isEditingInside
    }

    /// Whether a field of the sidebar's own is being typed into. The window's
    /// field editor stands in for whichever text field it is editing, and web
    /// content never answers as one.
    private var isEditingInside: Bool {
        guard let window, let editor = window.firstResponder as? NSTextView else { return false }
        let field = editor.isFieldEditor ? (editor.delegate as? NSView) ?? editor : editor
        guard field.window === window, !field.isHiddenOrHasHiddenAncestor else { return false }
        // Contained rather than overlapping: a floating card covers part of the
        // page, and a field of the page's own chrome lying partly beneath it is
        // not one of the sidebar's.
        return trackedRect.contains(convert(field.convert(field.bounds, to: nil), from: nil))
    }

    private var trackedRect: NSRect {
        bounds.intersection(visibleRect)
    }

    // MARK: - Initializers

    init(
        notificationCenter: NotificationCenter = .default,
        pointerLocation: @escaping @MainActor () -> NSPoint = { NSEvent.mouseLocation },
        onHoverChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.pointerLocation = pointerLocation
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
        // Modern NSView instances do not clip by default. Without this,
        // inVisibleRect can track the window beyond the sidebar's bounds.
        clipsToBounds = true
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
        notificationCenter.removeObserver(self)
        firstResponderObservation = nil
        trackingMenus.removeAll()
        heldPopovers.removeAllObjects()
        heldWindows.removeAllObjects()
        holdReleaseRevision += 1
        isReleasingHold = false
        lastReportedHover = nil
        scheduleEdgeRestCheck()
        guard let window else { return }
        let observations: [(Selector, Notification.Name, NSWindow?)] = [
            (#selector(menuTrackingBegan), NSMenu.didBeginTrackingNotification, nil),
            (#selector(menuTrackingEnded), NSMenu.didEndTrackingNotification, nil),
            (#selector(popoverWillShow), NSPopover.willShowNotification, nil),
            (#selector(popoverWillClose), NSPopover.willCloseNotification, nil),
            (#selector(anyWindowWillClose), NSWindow.willCloseNotification, nil),
            (#selector(windowResignedKey), NSWindow.didResignKeyNotification, window),
            (#selector(windowBecameKey), NSWindow.didBecomeKeyNotification, window),
        ]
        for (selector, name, object) in observations {
            notificationCenter.addObserver(self, selector: selector, name: name, object: object)
        }
        firstResponderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            // Settle after the field editor finishes taking over or handing back.
            DispatchQueue.main.async { [weak self] in
                self?.refreshPointerHover()
            }
        }
        schedulePointerRefresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        schedulePointerRefresh()
    }

    override func mouseEntered(with event: NSEvent) {
        refreshPointerHover()
    }

    override func mouseExited(with event: NSEvent) {
        refreshPointerHover()
    }

    func refreshPointerHover() {
        guard window != nil else { return }
        releaseWindowsNoLongerShown()
        if let edgeRest, edgeRest.point != pointerLocation() {
            self.edgeRest = nil
        }
        let isHovering =
            (isPointerInside && !hasPointerRestedAtScreenEdge) || (lastReportedHover == true && isHeldOpen)
        // A newly revealed sidebar starts offscreen while it slides in.
        // Absence before its first entry is not a pointer exit, unless the
        // pointer that revealed it has already left the window.
        guard isHovering || lastReportedHover != nil || hasRevealingPointerLeft else { return }
        guard isHovering != lastReportedHover else { return }
        lastReportedHover = isHovering
        scheduleEdgeRestCheck()
        onHoverChange(isHovering)
    }

    func schedulePointerRefresh() {
        // Attachment/layout may run inside SwiftUI's update. Read the settled
        // geometry on the next main-loop turn, without publishing during it.
        DispatchQueue.main.async { [weak self] in
            self?.refreshPointerHover()
        }
    }

    // MARK: - Actions - Edge Rest

    /// Samples the pointer while the sidebar is hovered and a rest delay is
    /// set. A pointer at rest produces no events, so only a sample can see
    /// how long it has stayed put.
    ///
    /// A rest outlives the hover it ended. The region stays attached until
    /// the sidebar is dismissed, and a refresh queued before then must not
    /// take the same motionless pointer for a new hover.
    private func scheduleEdgeRestCheck() {
        edgeRestRevision += 1
        let revision = edgeRestRevision
        guard edgeRestHideDelay > 0, window != nil else {
            edgeRest = nil
            return
        }
        guard lastReportedHover == true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.edgeRestCheckInterval) { [weak self] in
            guard let self, self.edgeRestRevision == revision else { return }
            self.sampleEdgeRest()
            self.refreshPointerHover()
            if self.edgeRestRevision == revision {
                self.scheduleEdgeRestCheck()
            }
        }
    }

    private func sampleEdgeRest() {
        let point = pointerLocation()
        guard let screen = window?.screen,
            point.x <= screen.frame.minX + 1 || point.x >= screen.frame.maxX - 1
        else {
            edgeRest = nil
            return
        }
        guard edgeRest?.point != point else { return }
        edgeRest = (point, Date())
    }

    // MARK: - Actions - Holds

    @objc private func menuTrackingBegan(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
            !trackingMenus.isEmpty || isPointerInside
        else { return }
        trackingMenus.insert(ObjectIdentifier(menu))
        refreshPointerHover()
    }

    @objc private func menuTrackingEnded(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
            trackingMenus.remove(ObjectIdentifier(menu)) != nil
        else { return }
        // This also covers Escape and selecting an action. Neither needs to
        // produce another mouse event to resolve the sidebar's visibility.
        beginHoldRelease()
    }

    /// Popovers are child windows that leave their parent key, so they are
    /// claimed as they open rather than when the keyboard moves. The window
    /// is not placed yet, so the keyboard stands in for where it came from.
    @objc private func popoverWillShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
            lastReportedHover == true,
            let window,
            let keyWindow = NSApp.keyWindow,
            keyWindow === window || isOpened(byThisWindow: keyWindow)
        else { return }
        heldPopovers.add(popover)
    }

    @objc private func popoverWillClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover, heldPopovers.contains(popover) else { return }
        heldPopovers.remove(popover)
        beginHoldRelease()
    }

    @objc private func anyWindowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, heldWindows.contains(closing) else { return }
        heldWindows.remove(closing)
        beginHoldRelease()
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        // AppKit has already made the next window key. One this window opened —
        // an extension's popup, a sheet, a popover taking typing — belongs to
        // whatever in the sidebar opened it.
        if lastReportedHover == true, let keyWindow = NSApp.keyWindow, isOpened(byThisWindow: keyWindow) {
            heldWindows.add(keyWindow)
        }
        refreshPointerHover()
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        // A popup that held the keyboard has been ordered out by now, even when
        // its close notification is still to come.
        refreshPointerHover()
    }

    private func isOpened(byThisWindow candidate: NSWindow) -> Bool {
        guard let window, candidate !== window else { return false }
        return sequence(first: candidate, next: { $0.parent ?? $0.sheetParent })
            .dropFirst()
            .contains { $0 === window }
    }

    private func releaseWindowsNoLongerShown() {
        let hidden = heldWindows.allObjects.filter { !$0.isVisible }
        guard !hidden.isEmpty else { return }
        hidden.forEach(heldWindows.remove)
        beginHoldRelease()
    }

    private func beginHoldRelease() {
        holdReleaseRevision += 1
        let revision = holdReleaseRevision
        isReleasingHold = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdReleaseDelay) { [weak self] in
            guard let self, self.holdReleaseRevision == revision else { return }
            self.isReleasingHold = false
            self.refreshPointerHover()
        }
    }
}
