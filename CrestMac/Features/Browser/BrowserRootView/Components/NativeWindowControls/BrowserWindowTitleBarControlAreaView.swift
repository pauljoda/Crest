import AppKit

/// The area of a control that sits under the window's title bar, such as the
/// Quick Window's address field, which keeps the control's presses while the
/// pointer is on it.
///
/// The window server drags a movable window from the whole strip under its
/// title bar before the app sees a press, and SwiftUI claims none of that strip
/// for the controls it hosts, so a drag across the field's text moved the
/// window instead of selecting it. While the pointer is on the area, the
/// window's title-bar guard (`BrowserWindowTitleBarGuard`) holds the window
/// still, as it does for a page there. The area takes no presses of its own,
/// and the chrome around it still moves the window.
@MainActor
final class BrowserWindowTitleBarControlAreaView: NSView {
    // MARK: - Variables

    /// The window whose guard holds this area's claim.
    private weak var claimedWindow: NSWindow?
    private var pointerCheckIsPending = false
    /// The window's full-screen notifications this area follows.
    private var fullScreenObservers: [NSObjectProtocol] = []

    // MARK: - Initializers

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The area follows the view's visible rect, and keeps reporting while a
        // button is held so a drag that leaves the control still ends the claim.
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
                owner: self
            ))
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Actions - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Actions - Tracking

    override func mouseEntered(with event: NSEvent) {
        update(at: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        update(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        release()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            release()
            stopFollowingFullScreen()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        followFullScreen()
        checkPointerSoon()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        checkPointerSoon()
    }

    override func viewDidHide() {
        super.viewDidHide()
        release()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        checkPointerSoon()
    }

    /// Checks the pointer where it is now, for an area that appeared or was
    /// resized under a pointer that has not moved. The check waits for the next
    /// turn of the main queue: the area's geometry changes during AppKit's
    /// layout, and the guard must not flush the window from inside it. A pointer
    /// over another window above this one is not on the area.
    private func checkPointerSoon() {
        guard !pointerCheckIsPending else { return }
        pointerCheckIsPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pointerCheckIsPending = false
            guard let window = self.window,
                NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
                    == window.windowNumber
            else {
                self.release()
                return
            }
            self.update(at: window.mouseLocationOutsideOfEventStream)
        }
    }

    private func update(at location: NSPoint) {
        guard let window, isUnderTitleBar(in: window), bounds.contains(convert(location, from: nil)) else {
            release()
            return
        }
        guard claimedWindow !== window else { return }
        release()
        claimedWindow = window
        BrowserWindowTitleBarGuard.guarding(window).claim(by: self)
    }

    private func release() {
        guard let claimedWindow else { return }
        self.claimedWindow = nil
        BrowserWindowTitleBarGuard.guarding(claimedWindow).release(by: self)
    }

    /// Whether the area reaches into the strip under `window`'s title bar. A
    /// window in fullscreen, or one whose content stops at its title bar, has
    /// no such strip. The whole area claims the window once any of it is in the
    /// strip, so a pointer that crosses into the strip on its way to a press has
    /// already made the window unmovable.
    private func isUnderTitleBar(in window: NSWindow) -> Bool {
        guard !window.styleMask.contains(.fullScreen), !isHiddenOrHasHiddenAncestor, let content = window.contentView
        else { return false }
        let titleBarBottom = window.contentLayoutRect.maxY
        return titleBarBottom < content.convert(content.bounds, to: nil).maxY
            && convert(bounds, to: nil).maxY > titleBarBottom
    }

    // MARK: - Actions - Full Screen

    /// Checks the pointer again as the window enters or leaves full screen. A
    /// window already as wide as the screen changes mode without resizing the
    /// area, so neither a frame change nor the pointer would end a claim that
    /// full screen no longer allows.
    private func followFullScreen() {
        stopFollowingFullScreen()
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification,
        ]
        fullScreenObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPointerSoon() }
            }
        }
    }

    private func stopFollowingFullScreen() {
        fullScreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullScreenObservers = []
    }
}
