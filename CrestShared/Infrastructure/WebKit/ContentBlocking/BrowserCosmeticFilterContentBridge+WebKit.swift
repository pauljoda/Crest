import Foundation
import WebKit

// MARK: - Actions - WebKit

extension BrowserCosmeticFilterContentBridge {
    static let contentWorld = WKContentWorld.world(name: "com.pauldavis.crest.cosmetics")

    /// Installs the bridge in every document `userContentController` serves.
    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserScriptMessageProxy {
        let proxy = BrowserScriptMessageProxy(receive: receive)
        userContentController.add(proxy, contentWorld: contentWorld, name: messageHandlerName)
        userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: contentWorld))
        return proxy
    }
}

/// WebKit delivers the cosmetic bridge through its own user content
/// controller and answers in the frame and content world that asked.
extension BrowserCosmeticFilterSession {
    convenience init(webView: WKWebView, core: CrestCore, spaceID: UUID, picker: BrowserElementPicker) {
        self.init(
            core: core, spaceID: spaceID, picker: picker, siteURL: { [weak webView] in webView?.url },
            evaluate: { [weak webView] body, arguments, frame in
                guard let webView, let frameInfo = frame.handle as? WKFrameInfo else { return nil }
                return try await webView.callAsyncJavaScript(
                    body, arguments: arguments, in: frameInfo,
                    contentWorld: BrowserCosmeticFilterContentBridge.contentWorld)
            })
    }

    func receive(_ scriptMessage: WKScriptMessage) {
        guard scriptMessage.name == BrowserCosmeticFilterContentBridge.messageHandlerName else { return }
        let origin = scriptMessage.frameInfo.securityOrigin
        receive(
            scriptMessage.body,
            from: BrowserContentFrame(
                isMainFrame: scriptMessage.frameInfo.isMainFrame, securityProtocol: origin.protocol, host: origin.host,
                port: origin.port, handle: scriptMessage.frameInfo))
    }
}
