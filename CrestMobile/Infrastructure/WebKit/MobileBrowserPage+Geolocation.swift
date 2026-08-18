import WebKit

extension MobileBrowserPage {
    func receiveGeolocationMessage(_ message: WKScriptMessage) {
        if let sourceWebView = message.webView, sourceWebView !== webView {
            host?.routeGeolocationMessage(message)
            return
        }
        geolocationCoordinator?.receive(message)
    }

    func beginGeolocationNavigation() {
        geolocationCoordinator?.beginNavigation()
    }

    func removeGeolocationRequests() {
        geolocationCoordinator?.cancelAll()
    }
}
