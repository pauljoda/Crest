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
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        if handleCapabilityBrokerWindowCreate(
            message,
            applicationIdentifier: applicationIdentifier,
            controller: controller,
            extensionContext: extensionContext,
            replyHandler: replyHandler
        ) {
            return
        }
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

    private func handleCapabilityBrokerWindowCreate(
        _ message: Any,
        applicationIdentifier: String?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard
            applicationIdentifier
                == BrowserExtensionNativeMessagingApplication
                .capabilityBrokerIdentifier,
            let request = message as? [String: Any],
            request["api"] as? String == "windows.create"
        else {
            return false
        }
        guard
            let authorization = verifiedNativeMessagingAuthorizations[
                ObjectIdentifier(extensionContext)
            ]
        else {
            replyHandler(
                nil,
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return true
        }
        guard authorization.allowsInternalCapabilityBroker else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.permissionDenied(
                    "internalCapabilityBroker"
                )
            )
            return true
        }
        guard
            let (spaceID, _) = verifiedSpaceAndEntry(
                controller: controller,
                context: extensionContext
            ),
            let createData = request["createData"] as? [String: Any],
            (createData["type"] as? String) == "popup",
            let url = capabilityBrokerWindowURL(
                from: createData["url"],
                extensionContext: extensionContext
            )
        else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.invalidRequest
            )
            return true
        }

        openAuxiliaryWindow(
            BrowserExtensionWindowPresentationRequest(
                url: url,
                title: extensionContext.webExtension.displayName ?? "Extension",
                frame: capabilityBrokerWindowFrame(from: createData),
                windowType: .popup,
                windowState: capabilityBrokerWindowState(from: createData),
                shouldFocus: (createData["focused"] as? Bool) != false
            ),
            in: spaceID,
            announceToController: true
        ) { window, error in
            guard error == nil, window != nil else {
                replyHandler(
                    nil,
                    error
                        ?? BrowserExtensionCapabilityBrokerError.serviceFailure(
                            "Crest could not present the extension window."
                        )
                )
                return
            }
            // The page-side compatibility wrapper now asks WebKit for this
            // window. Returning only presentation state avoids inventing an ID
            // that would disagree with windows.getAll/update/remove.
            replyHandler(["presented": true], nil)
        }
        return true
    }

    private func capabilityBrokerWindowURL(
        from value: Any?,
        extensionContext: WKWebExtensionContext
    ) -> URL? {
        let rawURL: String?
        if let value = value as? String {
            rawURL = value
        } else if let values = value as? [String], values.count == 1 {
            rawURL = values[0]
        } else {
            rawURL = nil
        }
        guard let rawURL, let url = URL(string: rawURL) else { return nil }
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            return url
        }
        guard
            scheme == extensionContext.baseURL.scheme?.lowercased(),
            url.host?.lowercased()
                == extensionContext.baseURL.host?.lowercased(),
            url.port == extensionContext.baseURL.port
        else {
            return nil
        }
        return url
    }

    private func capabilityBrokerWindowFrame(
        from createData: [String: Any]
    ) -> CGRect {
        func coordinate(_ key: String) -> CGFloat? {
            guard let value = createData[key] as? NSNumber else { return nil }
            let coordinate = value.doubleValue
            return coordinate.isFinite ? CGFloat(coordinate) : nil
        }
        let left = coordinate("left")
        let top = coordinate("top")
        let width = coordinate("width")
        let height = coordinate("height")
        guard left != nil || top != nil || width != nil || height != nil else {
            return .null
        }
        return CGRect(
            x: left ?? .nan,
            y: top ?? .nan,
            width: width ?? 0,
            height: height ?? 0
        )
    }

    private func capabilityBrokerWindowState(
        from createData: [String: Any]
    ) -> WKWebExtension.WindowState {
        switch createData["state"] as? String {
        case "minimized":
            .minimized
        case "maximized":
            .maximized
        case "fullscreen":
            .fullscreen
        default:
            .normal
        }
    }
}
