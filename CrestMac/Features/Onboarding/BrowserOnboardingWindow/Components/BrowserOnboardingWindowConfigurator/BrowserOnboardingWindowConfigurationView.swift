import AppKit

@MainActor
final class BrowserOnboardingWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        BrowserWindowAccessibility.pinTitle(
            BrowserOnboardingWindowActivation.windowTitle,
            on: window
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        // Setup ends with Start Browsing, or Cancel where it was opened for
        // one step, never by closing a window that leaves Crest without one.
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
