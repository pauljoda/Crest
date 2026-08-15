import SwiftUI

struct BrowserPlatformWebView: NSViewRepresentable {
    let page: BrowserPage

    func makeNSView(context: Context) -> BrowserWebHostView {
        let host = BrowserWebHostView()
        host.attach(page.webView)
        return host
    }

    func updateNSView(_ host: BrowserWebHostView, context: Context) {
        host.attach(page.webView)
    }

    static func dismantleNSView(_ host: BrowserWebHostView, coordinator: Void) {
        host.detach()
    }
}

#Preview("Platform Web View") {
    let preview = BrowserDetailPreviewFixture.makeWebContent()

    BrowserPlatformWebView(page: preview.page)
        .frame(width: 720, height: 480)
}
