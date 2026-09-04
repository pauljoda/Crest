import SwiftUI
import WebKit

struct BrowserExtensionSidebarWebView: NSViewRepresentable {
    let webView: WKWebView
    let userInteracted: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(webView: webView, userInteracted: userInteracted) }

    func makeNSView(context: Context) -> BrowserWebHostView {
        let host = BrowserWebHostView()
        host.attach(webView, focusRestoration: nil)
        return host
    }

    func updateNSView(_ host: BrowserWebHostView, context: Context) {
        webView.appearance = host.effectiveAppearance
        host.attach(webView, focusRestoration: nil)
    }

    static func dismantleNSView(_ host: BrowserWebHostView, coordinator: Coordinator) {
        coordinator.stop()
        host.detach()
    }

    @MainActor
    final class Coordinator {
        private var monitor: Any?

        init(webView: WKWebView, userInteracted: @escaping () -> Void) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
                [weak webView] event in
                guard let webView, let window = webView.window, event.window === window else { return event }
                let isInside: Bool
                if event.type == .keyDown {
                    isInside = (window.firstResponder as? NSView)?.isDescendant(of: webView) == true
                } else {
                    isInside = webView.bounds.contains(webView.convert(event.locationInWindow, from: nil))
                }
                if isInside { userInteracted() }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
