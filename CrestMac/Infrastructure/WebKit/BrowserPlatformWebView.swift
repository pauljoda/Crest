import SwiftUI

extension EnvironmentValues {
    @Entry var browserWebFocusRestorationGate =
        BrowserWebFocusRestorationGate.suppressed
}

struct BrowserPlatformWebView: NSViewRepresentable {
    let page: BrowserPage
    let isPageActive: Bool
    let focusRestorationGate: BrowserWebFocusRestorationGate

    func makeNSView(context: Context) -> BrowserWebHostView {
        let host = BrowserWebHostView()
        host.attach(
            page.webView,
            focusRestoration: page.focusRestoration
        )
        host.updateFocusPresentation(
            isPageActive: isPageActive,
            gate: focusRestorationGate
        )
        return host
    }

    func updateNSView(_ host: BrowserWebHostView, context: Context) {
        host.attach(
            page.webView,
            focusRestoration: page.focusRestoration
        )
        host.updateFocusPresentation(
            isPageActive: isPageActive,
            gate: focusRestorationGate
        )
    }

    static func dismantleNSView(_ host: BrowserWebHostView, coordinator: Void) {
        host.detach()
    }
}
