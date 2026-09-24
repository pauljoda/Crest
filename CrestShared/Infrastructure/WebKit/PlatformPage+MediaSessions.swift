import WebKit

extension BrowserPlatformPage {
    func receiveMediaSessionMessage(_ message: WKScriptMessage) {
        guard message.webView === webKitView else {
            host?.routeMediaSessionMessage(message)
            return
        }
        mediaSessionCoordinator?.receive(message)
        refreshMediaActivity()
    }

    /// Asks WebKit what media the page runs, and tells the core when that
    /// changed: playback the page's Media Session bridge saw start or stop,
    /// capture, or Picture in Picture.
    func refreshMediaActivity() {
        guard let engine = webKitEngine else { return }
        Task { @MainActor [weak self, weak engine] in
            guard let engine, await engine.refreshMediaActivity() else { return }
            self?.navigationReporter?.stateChanged()
        }
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
