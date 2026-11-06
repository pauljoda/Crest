import AppKit

/// Every window the shell opens. All native close routes, including
/// accessibility and traffic-light actions, pass through `close()`, which asks
/// the window's close gate first; AppKit still owns `performClose` and the
/// delegate's checks. A panel, so a Quick Window can open over another app's
/// full-screen Space; every other kind behaves as a plain window.
@MainActor
final class BrowserMacWindow: NSPanel {
    // MARK: - Variables

    /// A panel cannot become main by default; these windows can.
    override var canBecomeMain: Bool { true }

    var closeGate: BrowserWindowCloseGate?
    /// What the window's content does with a mouse's Back and Forward buttons
    /// and with swipes, while content that knows its pages is shown.
    weak var pointerNavigation: (any BrowserMacWindowPointerNavigation)?
    private var frameBeforeZoom: NSRect?
    private(set) var wasZoomedBeforeFullScreen = false

    /// The frame the window returns to after zoom or fullscreen. A normal
    /// window answers its current frame, including any extension-driven move.
    var restoredFrame: NSRect {
        isZoomed || styleMask.contains(.fullScreen) ? frameBeforeZoom ?? frame : frame
    }

    // MARK: - Actions - Window state

    override func zoom(_ sender: Any?) {
        if !isZoomed, !styleMask.contains(.fullScreen) { frameBeforeZoom = frame }
        super.zoom(sender)
    }

    /// Starts entering or leaving full screen on the next turn of the main
    /// queue. AppKit lays the window out as a transition starts, so the
    /// window's pages would join it on the stack of whoever asked. The
    /// Chromium engine asks from inside its own work on a tab, such as closing
    /// the tab that was full screen, and a page joining the window calls
    /// straight back into that work.
    override func toggleFullScreen(_ sender: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.startFullScreenTransition()
        }
    }

    private func startFullScreenTransition() {
        if !styleMask.contains(.fullScreen) {
            wasZoomedBeforeFullScreen = isZoomed
            if !isZoomed { frameBeforeZoom = frame }
        }
        super.toggleFullScreen(nil)
    }

    // MARK: - Actions - Closing

    override func close() {
        guard let closeGate else {
            super.close()
            return
        }
        guard closeGate.mayClose(then: { [weak self] in self?.closeAfterApproval() }) else { return }
        super.close()
    }

    /// Closes without asking: the gate approved it, or the shell closes the
    /// window as part of something wider it already decided.
    func closeAfterApproval() {
        super.close()
    }

    // MARK: - Actions - Swipes

    /// A swipe no view under the pointer took reaches the window: a Chromium
    /// page's, which its engine leaves to the browser window, or one a mouse
    /// sends for its Back and Forward actions. Like those buttons, it goes
    /// back or forward on the page under the pointer and switches Space over
    /// the sidebar; elsewhere it moves the window's active page. A WebKit page
    /// moves through its own swipes.
    override func swipe(with event: NSEvent) {
        if let action = BrowserSidebarMouseButtonAction(swipeDeltaX: event.deltaX),
            pointerNavigation?.navigate(action, swipedAt: event) == true
        {
            return
        }
        super.swipe(with: event)
    }
}
