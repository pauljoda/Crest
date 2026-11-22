import WebKit

// MARK: - Actions - WebKit

extension BrowserFirstPaintContentBridge {
    static let contentWorld = WKContentWorld.world(name: "com.pauldavis.crest.first-paint")

    /// Installs the bridge in every main document `controller` serves. A
    /// popup shares its opener's controller, so the report goes to the page
    /// that owns the web view it came from.
    static func install(in controller: WKUserContentController) {
        controller.add(
            BrowserScriptMessageProxy { message in
                guard message.frameInfo.isMainFrame else { return }
                (message.webView as? BrowserDesktopWebView)?.menuHost?.receive(BrowserPageContentPainted())
            },
            contentWorld: contentWorld, name: messageHandlerName
        )
        controller.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: contentWorld))
    }
}
