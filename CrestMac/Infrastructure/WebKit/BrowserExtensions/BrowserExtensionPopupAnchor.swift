import AppKit

@MainActor
final class BrowserExtensionPopupAnchor {
    let screenPoint: CGPoint
    private weak var sourceWindow: NSWindow?
    private weak var sourceView: NSView?
    private let fallbackOffset: CGPoint

    init(screenPoint: CGPoint, sourceWindow: NSWindow?) {
        self.screenPoint = screenPoint
        self.sourceWindow = sourceWindow
        sourceView = nil
        fallbackOffset = .zero
    }

    init(sourceView: NSView) {
        self.sourceView = sourceView
        sourceWindow = sourceView.window
        fallbackOffset = .zero
        guard let window = sourceView.window else {
            screenPoint = CGPoint(
                x: sourceView.bounds.midX,
                y: sourceView.bounds.midY
            )
            return
        }
        let windowRect = sourceView.convert(sourceView.bounds, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        screenPoint = CGPoint(x: screenRect.midX, y: screenRect.midY)
    }

    private init(
        screenPoint: CGPoint,
        sourceWindow: NSWindow?,
        sourceView: NSView?,
        fallbackOffset: CGPoint
    ) {
        self.screenPoint = screenPoint
        self.sourceWindow = sourceWindow
        self.sourceView = sourceView
        self.fallbackOffset = fallbackOffset
    }

    func offsetBy(
        dx: CGFloat = 0,
        dy: CGFloat = 0
    ) -> BrowserExtensionPopupAnchor {
        BrowserExtensionPopupAnchor(
            screenPoint: screenPoint,
            sourceWindow: sourceWindow,
            sourceView: sourceView,
            fallbackOffset: CGPoint(
                x: fallbackOffset.x + dx,
                y: fallbackOffset.y + dy
            )
        )
    }

    func replacingSourceWindow(
        _ window: NSWindow?
    ) -> BrowserExtensionPopupAnchor {
        BrowserExtensionPopupAnchor(
            screenPoint: CGPoint(
                x: screenPoint.x + fallbackOffset.x,
                y: screenPoint.y + fallbackOffset.y
            ),
            sourceWindow: window,
            sourceView: nil,
            fallbackOffset: .zero
        )
    }

    func contentView(fallbackWindow: NSWindow?) -> NSView? {
        sourceWindow?.contentView ?? fallbackWindow?.contentView
    }

    func presentationSource(
        fallbackWindow: NSWindow?
    ) -> (view: NSView, rect: CGRect)? {
        if let sourceView, sourceView.window != nil {
            return (sourceView, sourceView.bounds)
        }
        guard let hostView = contentView(fallbackWindow: fallbackWindow) else {
            return nil
        }
        let adjustedScreenPoint = CGPoint(
            x: screenPoint.x + fallbackOffset.x,
            y: screenPoint.y + fallbackOffset.y
        )
        let windowPoint =
            hostView.window?.convertPoint(
                fromScreen: adjustedScreenPoint
            ) ?? adjustedScreenPoint
        let interactionPoint = hostView.convert(windowPoint, from: nil)
        return (
            hostView,
            BrowserExtensionPopupAnchorPolicy.anchorRect(
                in: hostView.bounds,
                interactionPoint: interactionPoint
            )
        )
    }
}
