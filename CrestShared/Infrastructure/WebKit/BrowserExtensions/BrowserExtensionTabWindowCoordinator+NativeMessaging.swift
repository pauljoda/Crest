import Foundation
import WebKit
import os

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
        for context: WKWebExtensionContext,
        in owningSpaceID: SpaceID? = nil
    ) {
        let key = ObjectIdentifier(context)
        let resolvedSpaceID: SpaceID?
        if let owningSpaceID {
            resolvedSpaceID = owningSpaceID
        } else if let controller = context.webExtensionController,
            let (spaceID, _) = verifiedSpaceAndEntry(
                controller: controller,
                context: context
            )
        {
            resolvedSpaceID = spaceID
        } else {
            resolvedSpaceID = nil
        }
        if let resolvedSpaceID {
            pageProvider?.closeExtensionOffscreenDocument(
                extensionBaseURL: context.baseURL,
                in: resolvedSpaceID
            )
        }
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
        if handleCapabilityBrokerDiagnostics(
            message,
            applicationIdentifier: applicationIdentifier,
            extensionContext: extensionContext,
            replyHandler: replyHandler
        ) {
            return
        }
        if handleCapabilityBrokerOffscreen(
            message,
            applicationIdentifier: applicationIdentifier,
            controller: controller,
            extensionContext: extensionContext,
            replyHandler: replyHandler
        ) {
            return
        }
        if handleCapabilityBrokerDownload(
            message,
            applicationIdentifier: applicationIdentifier,
            controller: controller,
            extensionContext: extensionContext,
            replyHandler: replyHandler
        ) {
            return
        }
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

    /// Records what an extension's own JavaScript reported about itself.
    ///
    /// Not a capability, so it is answered before every permission-gated
    /// handler and asks for no grant: the payload is the extension's own error
    /// text arriving over the broker it is already authorized to use, and
    /// gating it behind a permission would silence exactly the extensions
    /// whose failures are hardest to see. Authorization still matters — an
    /// unverified context cannot file reports against a verified one.
    private func handleCapabilityBrokerDiagnostics(
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
            payload["api"] as? String == "diagnostics.report"
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
        let reportedMessage = Self.diagnosticsText(payload["message"])
        guard !reportedMessage.isEmpty else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.invalidRequest
            )
            return true
        }
        let rawKind = Self.diagnosticsText(payload["kind"], limit: 64)
        let kind = BrowserExtensionDiagnosticsReportKind(rawValue: rawKind)
        let source = Self.diagnosticsSourceLabel(payload["source"])
        let displayName =
            extensionContext.webExtension.displayName
            ?? extensionContext.uniqueIdentifier
        let identifier = extensionContext.uniqueIdentifier

        switch kind {
        case .consoleOutput:
            let level = Self.diagnosticsText(payload["level"], limit: 16)
            Self.diagnosticsLog.info(
                """
                \(displayName, privacy: .public) \
                [\(identifier, privacy: .public)] console.\
                \(level.isEmpty ? "log" : level, privacy: .public) at \
                \(source, privacy: .public): \
                \(reportedMessage, privacy: .public)
                """
            )
        case .messageTrace:
            // One line per message the extension sends or receives, so a
            // sender that waits forever can be told from a listener that
            // never claimed the reply.
            let op = Self.diagnosticsText(payload["op"], limit: 64)
            Self.diagnosticsLog.info(
                """
                \(displayName, privacy: .public) \
                [\(identifier, privacy: .public)] trace \
                \(op, privacy: .public) at \
                \(source, privacy: .public): \
                \(reportedMessage, privacy: .public)
                """
            )
        case .suppressed:
            Self.diagnosticsLog.notice(
                """
                \(displayName, privacy: .public) \
                [\(identifier, privacy: .public)] \
                \(reportedMessage, privacy: .public)
                """
            )
        case .uncaughtError, .unhandledRejection, .uncheckedLastError, nil:
            // The stack is the extension's own code trace, and the reason
            // this channel exists at all: without it a report names the fault
            // but not the line that raised it.
            let stack = Self.diagnosticsText(payload["stack"])
            Self.diagnosticsLog.error(
                """
                \(displayName, privacy: .public) \
                [\(identifier, privacy: .public)] \
                \(kind?.label ?? rawKind, privacy: .public) at \
                \(source, privacy: .public): \
                \(reportedMessage, privacy: .public)\
                \(stack.isEmpty ? "" : " | \(stack)", privacy: .public)
                """
            )
        }

        if kind?.appendsToRuntimeSummaryErrors == true {
            BrowserExtensionDiagnosticsLog.shared.record(
                Self.runtimeSummaryEntry(
                    kind: kind?.label ?? rawKind,
                    message: reportedMessage,
                    source: source,
                    payload: payload
                ),
                forContext: identifier
            )
        }
        replyHandler(["recorded": true], nil)
        return true
    }

    private static let diagnosticsLog = Logger(
        subsystem: ProductIdentity.serviceNamespace,
        category: "extension-diagnostics"
    )

    private static let diagnosticsTextLimit = 2000

    private static func diagnosticsText(
        _ value: Any?,
        limit: Int = diagnosticsTextLimit
    ) -> String {
        guard let text = value as? String else { return "" }
        let collapsed = text.replacingOccurrences(
            of: "\n",
            with: " "
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(limit))
    }

    /// The reporting document, with everything after its path removed.
    ///
    /// An extension page's query string and fragment can carry a page URL, an
    /// account name, or a one-time token the extension put there. The path is
    /// what identifies the popup or worker that failed, and it is all this
    /// channel logs.
    private static func diagnosticsSourceLabel(_ value: Any?) -> String {
        let raw = diagnosticsText(value, limit: 512)
        guard !raw.isEmpty else { return "unknown" }
        guard var components = URLComponents(string: raw),
            components.scheme != nil
        else {
            return raw == "worker" ? "worker" : "unknown"
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string ?? "unknown"
    }

    private static func runtimeSummaryEntry(
        kind: String,
        message: String,
        source: String,
        payload: [String: Any]
    ) -> String {
        let line = (payload["lineno"] as? NSNumber)?.intValue ?? 0
        let column = (payload["colno"] as? NSNumber)?.intValue ?? 0
        let location =
            line > 0
            ? "\(source):\(line):\(column)"
            : source
        return "\(kind) at \(location): \(message)"
    }

    private func handleCapabilityBrokerOffscreen(
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
            let payload = message as? [String: Any],
            let api = payload["api"] as? String,
            [
                "offscreen.createDocument",
                "offscreen.closeDocument",
                "offscreen.hasDocument",
            ].contains(api)
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
        guard authorization.allowsInternalCapabilityBroker,
            authorization.grants("offscreen")
        else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.permissionDenied(
                    "offscreen"
                )
            )
            return true
        }
        guard
            let (spaceID, _) = verifiedSpaceAndEntry(
                controller: controller,
                context: extensionContext
            ),
            let pageProvider
        else {
            replyHandler(nil, BrowserExtensionOffscreenDocumentError.unavailable)
            return true
        }

        switch api {
        case "offscreen.createDocument":
            let request: BrowserExtensionOffscreenDocumentRequest
            do {
                request = try BrowserExtensionOffscreenDocumentRequest(
                    message: payload,
                    extensionBaseURL: extensionContext.baseURL
                )
            } catch {
                replyHandler(nil, error)
                return true
            }
            Task { @MainActor in
                do {
                    try await pageProvider.createExtensionOffscreenDocument(
                        at: request.url,
                        extensionBaseURL: extensionContext.baseURL,
                        in: spaceID
                    )
                    replyHandler(["created": true], nil)
                } catch {
                    replyHandler(nil, error)
                }
            }
        case "offscreen.closeDocument":
            pageProvider.closeExtensionOffscreenDocument(
                extensionBaseURL: extensionContext.baseURL,
                in: spaceID
            )
            replyHandler(["closed": true], nil)
        case "offscreen.hasDocument":
            replyHandler(
                [
                    "hasDocument":
                        pageProvider
                        .hasExtensionOffscreenDocument(
                            extensionBaseURL: extensionContext.baseURL,
                            in: spaceID
                        )
                ],
                nil
            )
        default:
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.invalidRequest
            )
        }
        return true
    }

    private func handleCapabilityBrokerDownload(
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
            let payload = message as? [String: Any],
            payload["api"] as? String == "downloads.download"
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
        guard authorization.allowsInternalCapabilityBroker,
            authorization.grants("downloads"),
            let clientID = authorization.clientID
        else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.permissionDenied(
                    "downloads"
                )
            )
            return true
        }
        guard
            let (spaceID, _) = verifiedSpaceAndEntry(
                controller: controller,
                context: extensionContext
            ),
            let pageProvider
        else {
            replyHandler(
                nil,
                BrowserExtensionDownloadExecutionError.unavailable
            )
            return true
        }
        let request: BrowserExtensionDownloadRequest
        do {
            request = try BrowserExtensionDownloadRequest(
                message: payload,
                extensionBaseURL: extensionContext.baseURL
            )
        } catch {
            replyHandler(nil, error)
            return true
        }
        let invocation = webpageMenuRegistry.consumeDownloadInvocation(
            for: clientID
        )
        let targetTabID: TabID
        if let invocation {
            guard currentState?.space(spaceID)?.tab(invocation.tabID) != nil
            else {
                replyHandler(
                    nil,
                    BrowserExtensionDownloadExecutionError.unavailable
                )
                return true
            }
            targetTabID = invocation.tabID
        } else {
            guard
                let selectedTabID = currentState?.space(spaceID)?.selectedTabID
            else {
                replyHandler(
                    nil,
                    BrowserExtensionDownloadExecutionError.unavailable
                )
                return true
            }
            targetTabID = selectedTabID
        }
        Task { @MainActor in
            do {
                let downloadID = try await pageProvider.startExtensionDownload(
                    request,
                    for: targetTabID,
                    in: spaceID,
                    isUserInitiated: invocation != nil
                )
                replyHandler(["downloadID": downloadID], nil)
            } catch {
                replyHandler(nil, error)
            }
        }
        return true
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
