import Foundation
import WebKit
import os

extension BrowserExtensionTabWindowCoordinator {
    private static let externalMessageLog = Logger(
        subsystem: ProductIdentity.serviceNamespace,
        category: "extension-diagnostics"
    )

    /// Hands a web page's message to the extension's own
    /// `runtime.onMessageExternal` listeners and answers with their reply.
    ///
    /// The caller — `BrowserExtensionWebPageRuntimeRelay` — has already
    /// checked that the frame is one this extension declared itself
    /// externally connectable to and that the extension holds host access for
    /// it. This step only routes: it resolves the Space's client identity and
    /// waits, bounded, for the one-shot reply.
    ///
    /// `nil` is Chrome's "receiving end does not exist": no context of this
    /// extension is listening, no listener claimed the message, or the answer
    /// never came.
    func deliverExternalWebPageMessage(
        messageJSON: Data,
        sender: BrowserExtensionExternalMessageDelivery.Sender,
        to extensionID: String,
        in spaceID: SpaceID
    ) async -> Data? {
        let client = BrowserExtensionServiceClientID.scoped(
            extensionID: extensionID,
            spaceID: spaceID
        )
        guard externalMessageRegistry.hasWatchers(for: client) else {
            Self.externalMessageLog.info(
                "runtime.externalMessage \(extensionID, privacy: .public) has no listening context"
            )
            return nil
        }
        let response = await externalMessageRegistry.deliver(
            messageJSON: messageJSON,
            sender: sender,
            to: client
        )
        Self.externalMessageLog.info(
            "runtime.externalMessage \(extensionID, privacy: .public) \(response == nil ? "unanswered" : "replied", privacy: .public) bytes=\(response?.count ?? 0, privacy: .public)"
        )
        return response
    }

    /// The broker envelope carrying one delivery to the extension's
    /// `runtime.watch` port.
    ///
    /// `sender` is Chrome's shape for a web page that is not a tab: where the
    /// frame is, and nothing more. There is no `tab`, because a side panel is
    /// not one, and no `id`, because the sender is a website rather than an
    /// extension. A message that will not decode is dropped rather than
    /// delivered half-formed — the page's promise then settles on the
    /// registry's timeout, exactly as it would for a silent listener.
    func externalMessageEventMessage(
        _ delivery: BrowserExtensionExternalMessageDelivery
    ) -> [String: Any]? {
        guard
            let message = Self.externalMessageValue(delivery.messageJSON)
        else { return nil }
        return [
            "api": "runtime.externalMessage",
            "requestId": delivery.requestID,
            "message": message,
            "sender": [
                "url": delivery.sender.url,
                "origin": delivery.sender.origin,
                "frameId": delivery.sender.frameID,
            ] as [String: Any],
        ]
    }

    /// The extension's answer to one relayed delivery.
    ///
    /// `runtime` gates on no permission in Chrome and asks for none here: the
    /// handler requires only that the context is authorized to use the
    /// internal broker, the same reasoning that lets `runtime.getContexts` and
    /// `diagnostics.report` past the grant table. A reply that names no live
    /// delivery — a second context answering after the first, or one that
    /// arrives past the timeout — is accepted and dropped, exactly as Chrome
    /// drops a late `sendResponse`.
    func handleCapabilityBrokerExternalMessageReply(
        _ message: Any,
        applicationIdentifier: String?,
        extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard
            applicationIdentifier
                == BrowserExtensionNativeMessagingApplication
                .capabilityBrokerIdentifier,
            let payload = message as? [String: Any],
            payload["api"] as? String == "runtime.externalMessageReply"
        else {
            return false
        }
        guard
            let authorization = verifiedNativeMessagingAuthorizations[
                ObjectIdentifier(extensionContext)
            ],
            authorization.allowsInternalCapabilityBroker
        else {
            replyHandler(
                nil,
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return true
        }
        guard let requestID = payload["requestId"] as? String,
            !requestID.isEmpty
        else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.invalidRequest
            )
            return true
        }
        let responseJSON: Data?
        if payload["response"] == nil || payload["response"] is NSNull {
            responseJSON = nil
        } else if let encoded = Self.externalMessageJSON(payload["response"]) {
            responseJSON = encoded
        } else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.invalidRequest
            )
            return true
        }
        let matched = externalMessageRegistry.resolve(
            requestID: requestID,
            responseJSON: responseJSON
        )
        replyHandler(["ok": true, "matched": matched], nil)
        return true
    }

    /// JSON for a value that reached Crest from JavaScript, top-level scalars
    /// included. A page's message and an extension's reply are both allowed to
    /// be a bare string or number, which `JSONSerialization` writes only with
    /// `.fragmentsAllowed`.
    static func externalMessageJSON(_ value: Any?) -> Data? {
        guard let value, !(value is NSNull) else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed]
        )
    }

    static func externalMessageValue(_ json: Data?) -> Any? {
        guard let json else { return nil }
        return try? JSONSerialization.jsonObject(
            with: json,
            options: [.fragmentsAllowed]
        )
    }
}
