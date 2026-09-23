import WebKit

extension BrowserPlatformPage {
    func receiveMediaSessionMessage(_ message: WKScriptMessage) {
        guard message.webView === webKitView else {
            host?.routeMediaSessionMessage(message)
            return
        }
        mediaSessionCoordinator?.receive(message)
    }

    func performMediaSessionAction(
        _ action: BrowserMediaSessionAction,
        documentIdentifier: String
    ) {
        mediaSessionCoordinator?.perform(
            action,
            documentIdentifier: documentIdentifier
        )
    }

    func setMediaSessionMuted(
        _ muted: Bool,
        documentIdentifier: String
    ) {
        mediaSessionCoordinator?.setMuted(
            muted,
            documentIdentifier: documentIdentifier
        )
    }
}
