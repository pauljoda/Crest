import Foundation
import WebKit
import os

/// Carries `chrome.runtime.sendMessage(extensionID, …)` from a website framed
/// by a Crest-hosted extension document into that extension.
///
/// WebKit answers the same call itself for an ordinary browser tab. It cannot
/// answer one from a side panel: `WebExtensionContext::runtimeWebPageSendMessage`
/// resolves the sending page through `getTab(senderPageProxyIdentifier)` and
/// drops the message when that lookup fails, and Crest's side-panel web view is
/// deliberately never registered as a tab — Chrome's side panel is not a tab
/// either, which is why `sender.tab` is undefined there. The page sees a plain
/// `undefined` after a random delay, and Claude's Cowork panel reports "Can't
/// reach the Claude extension."
///
/// This handler is the missing route. It is reachable only from the user
/// content controller of the extension web views Crest builds — a browser tab
/// never installs it — and every message is checked twice before it is
/// delivered:
///
/// 1. The frame's URL must match the *named* extension's own
///    `externally_connectable.matches`. This is Chrome's rule, and it is
///    re-evaluated here rather than trusted from the page: the page-world
///    alias applies the same grammar, but a frame can reach the message
///    handler without it.
/// 2. The extension must hold host access for that URL, which is the second
///    half of WebKit's own web-page check.
///
/// A refusal is indistinguishable from an unanswered message — both settle as
/// `undefined`, which the alias reports as Chrome's "Could not establish
/// connection" — so a page cannot use this channel to probe which extensions
/// are installed.
@MainActor
final class BrowserExtensionWebPageRuntimeRelay: NSObject,
    WKScriptMessageHandlerWithReply
{
    static let messageHandlerName = "crestExtensionWebPageRuntimeRelay"
    static let contentWorld = WKContentWorld.page

    private static let log = Logger(
        subsystem: ProductIdentity.serviceNamespace,
        category: "extension-diagnostics"
    )

    /// What the relay needs to know about one installed extension. Supplied as
    /// closures so the validation can be exercised without a loaded
    /// `WKWebExtensionContext`.
    struct Target {
        let externallyConnectableMatchPatterns: [String]
        let hasHostAccess: @MainActor (URL) -> Bool
        let deliver:
            @MainActor (
                _ messageJSON: Data,
                _ sender: BrowserExtensionExternalMessageDelivery.Sender
            ) async -> Data?

        init(
            externallyConnectableMatchPatterns: [String],
            hasHostAccess: @escaping @MainActor (URL) -> Bool,
            deliver:
                @escaping @MainActor (
                    Data, BrowserExtensionExternalMessageDelivery.Sender
                ) async -> Data?
        ) {
            self.externallyConnectableMatchPatterns =
                externallyConnectableMatchPatterns
            self.hasHostAccess = hasHostAccess
            self.deliver = deliver
        }
    }

    typealias Resolve = @MainActor (_ extensionID: String) -> Target?

    private let resolveTarget: Resolve
    private let reportsDiagnostics: Bool
    /// Chrome numbers the frames of a page; WebKit publishes no frame identity
    /// to the app, so Crest mints one. The panel's own document is frame 0 and
    /// each framed URL takes the next number, stable for the life of the
    /// relay. Nothing in an extension can resolve these further — they exist so
    /// a listener that reads `sender.frameId` sees a number rather than
    /// `undefined`.
    private var frameIDs: [String: Int] = [:]
    private var nextFrameID = 1

    init(reportsDiagnostics: Bool = false, resolveTarget: @escaping Resolve) {
        self.reportsDiagnostics = reportsDiagnostics
        self.resolveTarget = resolveTarget
    }

    /// The page's promise resolves with the extension's answer, and with
    /// `nil` for everything else. A refusal never becomes a rejection: an
    /// error message would tell a website whether the extension it named is
    /// installed and whether it declared that site externally connectable.
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
            let extensionID = body["extensionId"] as? String,
            !extensionID.isEmpty
        else {
            return (nil, nil)
        }
        let frameURL =
            message.frameInfo.request.url
            ?? Self.originURL(of: message.frameInfo.securityOrigin)
        let response = await relayedResponse(
            extensionID: extensionID,
            message: body["message"],
            frameURL: frameURL,
            isMainFrame: message.frameInfo.isMainFrame
        )
        return (response, nil)
    }

    /// The extension's answer, or `nil` for every refusal and every message
    /// nobody claimed. Exposed for tests; the message handler is a thin shell
    /// over it.
    func relayedResponse(
        extensionID: String,
        message: Any?,
        frameURL: URL?,
        isMainFrame: Bool
    ) async -> Any? {
        guard let frameURL, let target = resolveTarget(extensionID) else {
            report(extensionID: extensionID, outcome: "unknown-extension")
            return nil
        }
        guard
            BrowserExtensionMatchPatternPolicy.matches(
                url: frameURL,
                anyOf: target.externallyConnectableMatchPatterns
            )
        else {
            report(extensionID: extensionID, outcome: "not-externally-connectable")
            return nil
        }
        guard target.hasHostAccess(frameURL) else {
            report(extensionID: extensionID, outcome: "no-host-access")
            return nil
        }
        guard
            let messageJSON =
                BrowserExtensionTabWindowCoordinator.externalMessageJSON(
                    message
                )
        else {
            report(extensionID: extensionID, outcome: "unencodable-message")
            return nil
        }
        let sender = BrowserExtensionExternalMessageDelivery.Sender(
            url: frameURL.absoluteString,
            origin: Self.origin(of: frameURL),
            frameID: frameID(for: frameURL, isMainFrame: isMainFrame)
        )
        let responseJSON = await target.deliver(messageJSON, sender)
        report(
            extensionID: extensionID,
            outcome: responseJSON == nil ? "unanswered" : "replied"
        )
        return BrowserExtensionTabWindowCoordinator.externalMessageValue(
            responseJSON
        )
    }

    private func frameID(for url: URL, isMainFrame: Bool) -> Int {
        guard !isMainFrame else { return 0 }
        let key = url.absoluteString
        if let existing = frameIDs[key] { return existing }
        let assigned = nextFrameID
        nextFrameID += 1
        frameIDs[key] = assigned
        return assigned
    }

    /// The frame's origin as a URL, for the rare frame whose `request` WebKit
    /// leaves empty. A pattern with a path glob will not match it, which is
    /// the conservative outcome: the message is refused rather than delivered
    /// on an assumed path.
    static func originURL(of origin: WKSecurityOrigin) -> URL? {
        guard !origin.protocol.isEmpty, !origin.host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        if origin.port != 0 { components.port = origin.port }
        components.path = "/"
        return components.url
    }

    /// Scheme, host and non-default port, with no path — the shape Chrome puts
    /// in `sender.origin`.
    static func origin(of url: URL) -> String {
        guard
            var components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else { return "" }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string ?? ""
    }

    /// Outcomes only. The payload of a relayed message is the page's own
    /// content — for a sign-in hand-back it holds an authorization code — and
    /// never reaches a log.
    private func report(extensionID: String, outcome: String) {
        guard reportsDiagnostics else { return }
        Self.log.info(
            "runtime relay → \(extensionID, privacy: .public) \(outcome, privacy: .public)"
        )
    }
}
