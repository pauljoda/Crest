import AppKit

/// Owns hover across the sidebar's full region, including its leading inset.
/// Menu tracking can leave an exit queued after the pointer has returned to
/// the sidebar. Sample the current position instead of trusting that event,
/// and hold the region open until a menu started inside it finishes tracking.
@MainActor
final class BrowserSidebarHoverTrackingView: NSView {
    var onHoverChange: @MainActor @Sendable (Bool) -> Void
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue, !isEnabled else { return }
            trackingMenus.removeAll()
            lastReportedHover = nil
        }
    }

    private let notificationCenter: NotificationCenter
    private let pointerLocation: @MainActor () -> NSPoint
    private var trackingArea: NSTrackingArea?
    private var trackingMenus: Set<ObjectIdentifier> = []
    private var lastReportedHover: Bool?

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notificationCenter.removeObserver(self)
        trackingMenus.removeAll()
        lastReportedHover = nil
        guard let window else { return }
        notificationCenter.addObserver(
            self, selector: #selector(menuTrackingBegan),
            name: NSMenu.didBeginTrackingNotification, object: nil
        )
        notificationCenter.addObserver(
            self, selector: #selector(menuTrackingEnded),
            name: NSMenu.didEndTrackingNotification, object: nil
        )
        notificationCenter.addObserver(
            self, selector: #selector(windowResignedKey),
            name: NSWindow.didResignKeyNotification, object: window
        )
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
        guard isEnabled, window != nil else { return }
        let isHovering = !trackingMenus.isEmpty || isPointerInside
        // A newly revealed sidebar starts offscreen while it slides in.
        // Absence before its first entry is not a pointer exit.
        guard isHovering || lastReportedHover != nil else { return }
        guard isHovering != lastReportedHover else { return }
        lastReportedHover = isHovering
        onHoverChange(isHovering)
    }

    func schedulePointerRefresh() {
        // Attachment/layout may run inside SwiftUI's update. Read the settled
        // geometry on the next main-loop turn, without publishing during it.
        DispatchQueue.main.async { [weak self] in
            self?.refreshPointerHover()
        }
    }

    private var isPointerInside: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return false }
        let location = convert(window.convertPoint(fromScreen: pointerLocation()), from: nil)
        return bounds.intersection(visibleRect).contains(location)
    }

    @objc private func menuTrackingBegan(_ notification: Notification) {
        guard isEnabled, let menu = notification.object as? NSMenu,
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
        refreshPointerHover()
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        refreshPointerHover()
    }
}
