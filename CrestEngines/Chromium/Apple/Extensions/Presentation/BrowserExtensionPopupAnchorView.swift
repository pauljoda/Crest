import AppKit

@MainActor
final class BrowserExtensionPopupAnchorView: NSView {
    var popupAnchorDidChange: ((BrowserExtensionPopupAnchor) -> Void)?
    private var publishedScreenCenter: CGPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
