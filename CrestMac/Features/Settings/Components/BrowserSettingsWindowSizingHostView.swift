import AppKit

@MainActor
final class BrowserSettingsWindowSizingHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowSizing()
    }

    func applyWindowSizing() {
        guard let window else { return }
        BrowserSettingsWindowSizing.apply(to: window)
    }
}
