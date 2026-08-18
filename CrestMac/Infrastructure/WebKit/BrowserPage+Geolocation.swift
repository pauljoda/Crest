import WebKit

extension BrowserPage {
    func receiveGeolocationMessage(_ message: WKScriptMessage) {
        if let sourceWebView = message.webView, sourceWebView !== webView {
            host?.routeGeolocationMessage(message)
            return
        }
        geolocationCoordinator?.receive(message)
    }

    func synchronizeGeolocationPermission() {
        geolocationCoordinator?.synchronizeMainFramePermission()
    }

    func beginGeolocationNavigation() {
        geolocationCoordinator?.beginNavigation()
    }

    func removeGeolocationRequests() {
        geolocationCoordinator?.cancelAll()
    }
}
