import Foundation
import WebKit

/// Answers the `Target` and `Emulation` commands a session receives about
/// itself. A session sees one target — its own tab — because attachment is the
/// grant: enumerating the window's other tabs here would report pages the user
/// never consented to expose.
@MainActor
final class BrowserChromeDebuggerTarget {
    private let target: BrowserExtensionDebuggerTarget
    private weak var webView: WKWebView?
    private weak var tabHost: (any BrowserExtensionDebuggerTabHosting)?

    init(
        target: BrowserExtensionDebuggerTarget, webView: WKWebView,
        tabHost: (any BrowserExtensionDebuggerTabHosting)?
    ) {
        self.target = target
        self.webView = webView
        self.tabHost = tabHost
    }

    var targetID: String { target.tabID.rawValue.uuidString }

    func execute(_ method: String, parameters: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        switch method {
        case "Target.getTargets":
            return ["targetInfos": [targetInfo()]]
        case "Target.closeTarget":
            guard let requested = parameters["targetId"] as? String else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("targetId")
            }
            guard requested == targetID else {
                // A session may only close the tab it is attached to.
                throw BrowserChromeDebuggerProtocolError.invalidParameter("targetId")
            }
            guard let tabHost else { throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method) }
            try await tabHost.debuggerCloseTab(for: target)
            return ["success": true]
        case "Emulation.setDeviceMetricsOverride", "Emulation.clearDeviceMetricsOverride":
            // WebKit's `Page.setScreenSizeOverride` changes only what the page
            // reports for the screen, not its viewport, device pixel ratio, or
            // touch emulation. Answering with it would let a client lay a page
            // out for a size it was never given, so the command is refused.
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method)
        default:
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method)
        }
    }

    private func targetInfo() -> [String: Any] {
        [
            "targetId": targetID,
            "type": "page",
            "title": webView?.title ?? "",
            "url": webView?.url?.absoluteString ?? "",
            "attached": true,
            // Crest never hands a debugger session an opener it could reach.
            "canAccessOpener": false,
            "browserContextId": target.spaceID.rawValue.uuidString,
        ]
    }
}
