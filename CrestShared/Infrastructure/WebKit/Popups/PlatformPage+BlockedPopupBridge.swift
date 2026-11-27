import Foundation
import WebKit

private struct BlockedPopupBridgeMessage: Decodable {
    let version: Int?
    let event: String?
    let userActivated: Bool?
    let documentIdentifier: String?

    init?(body: Any) {
        guard JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body),
            let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = decoded
    }

    var validatedDocumentIdentifier: String? {
        guard version == 1, event == "blocked", userActivated == false,
            let documentIdentifier, BrowserContentMessage.isValidIdentity(documentIdentifier)
        else { return nil }
        return documentIdentifier
    }
}

/// Blocked-popup reports from the WebKit content bridge.
extension BrowserPlatformPage {
    func receiveBlockedPopupMessage(_ message: WKScriptMessage) {
        if let sourceWebView = message.webView, sourceWebView !== webKitView {
            host?.routeBlockedPopupMessage(message)
            return
        }
        guard message.webView === webKitView,
            message.name == BrowserBlockedPopupContentBridge.messageHandlerName,
            message.frameInfo.isMainFrame,
            let documentIdentifier = BlockedPopupBridgeMessage(body: message.body)?.validatedDocumentIdentifier,
            let frameURL = message.frameInfo.request.url,
            let origin = SiteOrigin(url: frameURL),
            let currentURL = webKitView?.url,
            SiteOrigin(url: currentURL) == origin,
            !permissionCenter.decision(for: .popups, origin: origin, in: spaceID).grants
        else { return }

        var nextState = blockedPopupState
        guard
            nextState.recordBlockedAttempt(
                documentIdentifier: documentIdentifier,
                origin: origin
            )
        else { return }
        blockedPopupState = nextState
    }
}
