import AppKit

@MainActor
final class BrowserExtensionPopupAnchorView: NSView, BrowserExtensionAnchorStandingView {
    var popupAnchorDidChange: ((BrowserExtensionPopupAnchor) -> Void)?
    /// How strongly the control behind this view stands for its extension
    /// action, which decides between copies of it in one window.
    var standing = BrowserExtensionAnchorStanding.window
    /// The control this view stands for in the keyboard-anchor registry.
    var site: BrowserExtensionToolbarAnchorRegistry.Site? {
        didSet {
            guard site != oldValue else { return }
            if let oldValue {
                BrowserExtensionToolbarAnchorRegistry.unregister(self, as: oldValue)
            }
            if let site, window != nil {
                BrowserExtensionToolbarAnchorRegistry.register(self, as: site)
            }
        }
    }
    private var publishedScreenCenter: CGPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let site {
            if window != nil {
                BrowserExtensionToolbarAnchorRegistry.register(self, as: site)
            } else {
                BrowserExtensionToolbarAnchorRegistry.unregister(self, as: site)
            }
        }
        publishScreenCenter()
    }

    override func layout() {
        super.layout()
        publishScreenCenter()
    }

    private func publishScreenCenter() {
        guard let window else { return }
        let windowRect = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        let center = CGPoint(x: screenRect.midX, y: screenRect.midY)
        guard center != publishedScreenCenter else { return }
        publishedScreenCenter = center
        popupAnchorDidChange?(BrowserExtensionPopupAnchor(sourceView: self))
    }
}
