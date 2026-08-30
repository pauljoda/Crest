import AppKit
import WebKit

extension BrowserPagePool: BrowserExtensionPageProviding {
    func presentExtensionWindow(
        _ request: BrowserExtensionWindowPresentationRequest,
        in space: BrowserSpace,
        didFocus: @escaping (TabID) -> Void,
        didClose: @escaping (TabID) -> Void
    ) -> (any BrowserExtensionWindowPresentation)? {
        guard
            let lease = makeTransientPageLease(
                url: request.url,
                in: space
            ), let webView = lease.page?.webView
        else {
            return nil
        }
        return BrowserExtensionNativeWindowPresentation(
            request: request,
            lease: lease,
            webView: webView,
            didFocus: didFocus,
            didClose: didClose
        )
    }
}

@MainActor
private final class BrowserExtensionNativeWindowPresentation: NSObject,
    BrowserExtensionWindowPresentation,
    NSWindowDelegate
{
    let extensionTabID: TabID

    private let lease: BrowserTransientPageLease
    private let window: NSWindow
    private let didFocus: (TabID) -> Void
    private let didClose: (TabID) -> Void
    private var hasClosed = false

    init(
        request: BrowserExtensionWindowPresentationRequest,
        lease: BrowserTransientPageLease,
        webView: WKWebView,
        didFocus: @escaping (TabID) -> Void,
        didClose: @escaping (TabID) -> Void
    ) {
        extensionTabID = lease.extensionTabID
        self.lease = lease
        self.didFocus = didFocus
        self.didClose = didClose
        window = NSWindow(
            contentRect: BrowserExtensionNativeWindowFramePolicy.resolve(
                request.frame
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.delegate = self
        window.isReleasedWhenClosed = false
        window.title = request.title
        window.titleVisibility = .hidden
        window.minSize = BrowserExtensionNativeWindowFramePolicy.minimumSize
        let appearance =
            NSApp.keyWindow?.effectiveAppearance
            ?? NSApp.effectiveAppearance
        window.appearance = appearance
        webView.appearance = appearance
        window.contentView = webView
        window.identifier = NSUserInterfaceItemIdentifier(
            "extension-window-\(extensionTabID.rawValue.uuidString)"
        )

        if request.shouldFocus {
            focus()
        } else {
            window.orderFront(nil)
        }
        apply(request.windowState)
    }

    var geometry: BrowserExtensionWindowGeometry {
        let state: WKWebExtension.WindowState =
            if window.isMiniaturized {
                .minimized
            } else if window.styleMask.contains(.fullScreen) {
                .fullscreen
            } else if window.isZoomed {
                .maximized
            } else {
                .normal
            }
        return BrowserExtensionWindowGeometry(
            frame: window.frame,
            screenFrame: window.screen?.frame ?? NSScreen.main?.frame ?? .null,
            state: state
        )
    }

    func focus() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        didFocus(extensionTabID)
    }

    func windowWillClose(_ notification: Notification) {
        guard !hasClosed else { return }
        hasClosed = true
        lease.release()
        didClose(extensionTabID)
    }

    private func apply(_ state: WKWebExtension.WindowState) {
        switch state {
        case .normal:
            break
        case .minimized:
            window.miniaturize(nil)
        case .maximized:
            window.zoom(nil)
        case .fullscreen:
            window.toggleFullScreen(nil)
        @unknown default:
            break
        }
    }
}

private enum BrowserExtensionNativeWindowFramePolicy {
    static let minimumSize = CGSize(width: 360, height: 480)
    private static let defaultSize = CGSize(width: 520, height: 720)

    static func resolve(_ requested: CGRect) -> CGRect {
        let visibleFrame =
            NSScreen.main?.visibleFrame
            ?? CGRect(origin: .zero, size: CGSize(width: 1440, height: 900))
        let requestedWidth = requested.size.width
        let requestedHeight = requested.size.height
        let width = min(
            max(
                requestedWidth.isFinite && requestedWidth > 0
                    ? requestedWidth : defaultSize.width,
                minimumSize.width
            ),
            visibleFrame.width
        )
        let height = min(
            max(
                requestedHeight.isFinite && requestedHeight > 0
                    ? requestedHeight : defaultSize.height,
                minimumSize.height
            ),
            visibleFrame.height
        )
        let centeredOrigin = CGPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        let requestedX = requested.origin.x
        let requestedY = requested.origin.y
        let unclampedOrigin = CGPoint(
            x: requestedX.isFinite ? requestedX : centeredOrigin.x,
            y: requestedY.isFinite ? requestedY : centeredOrigin.y
        )
        return CGRect(
            x: min(
                max(unclampedOrigin.x, visibleFrame.minX),
                visibleFrame.maxX - width
            ),
            y: min(
                max(unclampedOrigin.y, visibleFrame.minY),
                visibleFrame.maxY - height
            ),
            width: width,
            height: height
        )
    }
}
