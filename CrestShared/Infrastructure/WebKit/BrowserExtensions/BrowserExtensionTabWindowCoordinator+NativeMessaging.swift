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

    func registerVerifiedChromeExtension(
        _ extensionID: BrowserChromeExtensionID,
        for context: WKWebExtensionContext
    ) {
        verifiedChromeExtensionIDs[ObjectIdentifier(context)] = extensionID
    }

    func unregisterNativeMessagingIdentity(
        for context: WKWebExtensionContext
    ) {
        verifiedChromeExtensionIDs[ObjectIdentifier(context)] = nil
    }

    func webExtensionController(
        _: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard
            let extensionID = verifiedChromeExtensionIDs[
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
            extensionID: extensionID,
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
            let extensionID = verifiedChromeExtensionIDs[
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
            extensionID: extensionID,
            completionHandler: completionHandler
        )
    }
}
