import WebKit

extension BrowserExtensionTabWindowCoordinator {
    var nativeMessagingCapability: BrowserExtensionNativeMessagingCapability {
        nativeMessagingHandler?.capability ?? .unavailableOnPlatform
    }

    func setNativeMessagingHandler(
        _ handler: BrowserExtensionNativeMessagingHandling?
    ) {
        nativeMessagingHandler = handler
    }

    func registerVerifiedNativeMessagingIdentity(
        _ identity: BrowserExtensionNativeMessagingIdentity,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        for context: WKWebExtensionContext
    ) {
        let key = ObjectIdentifier(context)
        verifiedNativeMessagingIdentities[key] = identity
        verifiedNativeMessagingAuthorizations[key] = authorization
    }

    func registerCapabilityBrokerAuthorization(
        _ authorization: BrowserExtensionNativeMessagingAuthorization,
        for context: WKWebExtensionContext
    ) {
        verifiedNativeMessagingAuthorizations[ObjectIdentifier(context)] =
            authorization
    }

    func unregisterNativeMessagingIdentity(
        for context: WKWebExtensionContext
    ) {
        let key = ObjectIdentifier(context)
        verifiedNativeMessagingIdentities[key] = nil
        verifiedNativeMessagingAuthorizations[key] = nil
    }

    func webExtensionController(
        _: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard
            let nativeMessagingHandler,
            let authorization = verifiedNativeMessagingAuthorizations[
                ObjectIdentifier(extensionContext)
            ]
        else {
            replyHandler(
                nil,
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return
        }
        let extensionIdentity = verifiedNativeMessagingIdentities[
            ObjectIdentifier(extensionContext)
        ]
        guard
            extensionIdentity != nil
                || applicationIdentifier
                    == BrowserExtensionNativeMessagingApplication
                    .capabilityBrokerIdentifier
        else {
            replyHandler(
                nil,
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return
        }
        nativeMessagingHandler.sendMessage(
            message,
            applicationIdentifier: applicationIdentifier,
            extensionIdentity: extensionIdentity,
            authorization: authorization,
            replyHandler: replyHandler
        )
    }

    func webExtensionController(
        _: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard
            let nativeMessagingHandler,
            let authorization = verifiedNativeMessagingAuthorizations[
                ObjectIdentifier(extensionContext)
            ]
        else {
            completionHandler(
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return
        }
        let extensionIdentity = verifiedNativeMessagingIdentities[
            ObjectIdentifier(extensionContext)
        ]
        guard
            extensionIdentity != nil
                || port.applicationIdentifier
                    == BrowserExtensionNativeMessagingApplication
                    .capabilityBrokerIdentifier
        else {
            completionHandler(
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return
        }
        nativeMessagingHandler.connect(
            port: port,
            extensionIdentity: extensionIdentity,
            authorization: authorization,
            completionHandler: completionHandler
        )
    }
}
