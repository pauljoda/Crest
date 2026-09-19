import SwiftUI

extension EnvironmentValues {
    @Entry var browserPagePresentationWindowID: BrowserWindowID? = nil
    @Entry var browserWebFocusRestorationGate =
        BrowserWebFocusRestorationGate.suppressed
}

struct BrowserPlatformWebView: NSViewRepresentable {
    @Environment(\.browserPagePresentationWindowID) private var presentationWindowID
    let page: BrowserPage
    let isPageActive: Bool
    let focusRestorationGate: BrowserWebFocusRestorationGate

    func makeNSView(context: Context) -> BrowserWebHostView {
        let host = BrowserWebHostView()
        host.attach(
            page.nativeView,
            focusRestoration: page.focusRestoration,
            allowsAttachment: allowsAttachment
        )
        host.updateFocusPresentation(
            isPageActive: isPageActive,
            gate: focusRestorationGate
        )
        return host
    }

    func updateNSView(_ host: BrowserWebHostView, context: Context) {
        host.attach(
            page.nativeView,
            focusRestoration: page.focusRestoration,
            allowsAttachment: allowsAttachment
        )
        host.updateFocusPresentation(
            isPageActive: isPageActive,
            gate: focusRestorationGate
        )
    }

    static func dismantleNSView(_ host: BrowserWebHostView, coordinator: Void) {
        host.detach()
    }

    private var allowsAttachment: Bool {
        guard let presentationWindowID, let owner = page.windowRouting?.pool else { return true }
        return owner.windowID == presentationWindowID
    }
}

// WebKit's hover observer remains with its adapter. Other native engine views
// use the same host without inheriting WebKit-specific presentation work.
extension BrowserDesktopWebView: BrowserNativePageSurfaceLifecycle {
    func didAttach(to host: BrowserWebHostView) { linkHover?.attach(to: host) }
    func willDetach(from host: BrowserWebHostView) { linkHover?.detach(from: host) }
}
