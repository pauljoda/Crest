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
        for context: WKWebExtensionContext
    ) {
        verifiedNativeMessagingIdentities[ObjectIdentifier(context)] = identity
    }

    func unregisterNativeMessagingIdentity(
        for context: WKWebExtensionContext
    ) {
        verifiedNativeMessagingIdentities[ObjectIdentifier(context)] = nil
    }

    func webExtensionController(
        _: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard
            let extensionIdentity = verifiedNativeMessagingIdentities[
                ObjectIdentifier(extensionContext)
            ], let nativeMessagingHandler
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
            let extensionIdentity = verifiedNativeMessagingIdentities[
                ObjectIdentifier(extensionContext)
            ], let nativeMessagingHandler
        else {
            completionHandler(
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return
        }
        nativeMessagingHandler.connect(
            port: port,
            extensionIdentity: extensionIdentity,
            completionHandler: completionHandler
        )
    }
}
