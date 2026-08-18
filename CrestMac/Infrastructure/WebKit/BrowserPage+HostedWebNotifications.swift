import AppKit
import Foundation
import WebKit

extension BrowserPage {
    func synchronizeHostedWebNotificationPermission() {
        guard let currentURL = displayURL ?? webView.url,
            let origin = BrowserSiteOrigin(url: currentURL)
        else {
            return
        }
        let documentIdentifier = hostedNotificationDocumentIdentifier
        Task { @MainActor [weak self] in
            await self?.sendHostedNotificationPermission(
                requestID: "site-controls",
                origin: origin,
                requestsSystemAuthorization: false,
                documentIdentifier: documentIdentifier,
                frame: nil
            )
        }
    }

    func receiveHostedWebNotificationMessage(_ message: WKScriptMessage) {
        if let sourceWebView = message.webView, sourceWebView !== webView {
            host?.routeHostedWebNotificationMessage(message)
            return
        }
        guard hostedNotificationCenter != nil,
            message.webView === webView,
            message.frameInfo.isMainFrame,
            let requestURL = message.frameInfo.request.url,
            let origin = BrowserSiteOrigin(url: requestURL),
            BrowserHostedWebNotificationOriginPolicy.allows(origin),
            let body = message.body as? [String: Any],
            (body["version"] as? Int) == 1,
            let action = body["action"] as? String
        else { return }
        let documentIdentifier = hostedNotificationDocumentIdentifier

        switch action {
        case "queryPermission":
            guard let requestID = body["requestID"] as? String,
                isValidHostedWebNotificationIdentifier(requestID)
            else { return }
            Task { @MainActor [weak self] in
                await self?.sendHostedNotificationPermission(
                    requestID: requestID,
                    origin: origin,
                    requestsSystemAuthorization: false,
                    documentIdentifier: documentIdentifier,
                    frame: message.frameInfo
                )
            }
        case "requestPermission":
            guard let requestID = body["requestID"] as? String,
                isValidHostedWebNotificationIdentifier(requestID)
            else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let userActivation = await hasActiveUserGesture(in: message.frameInfo)
                await resolveHostedNotificationPermission(
                    requestID: requestID,
                    origin: origin,
                    hasUserActivation: userActivation,
                    documentIdentifier: documentIdentifier,
                    frame: message.frameInfo
                )
            }
        case "create":
            guard let identifier = body["identifier"] as? String,
                isValidHostedWebNotificationIdentifier(identifier),
                let title = body["title"] as? String,
                let notificationBody = body["body"] as? String
            else { return }
            let isSilent = body["silent"] as? Bool ?? false
            Task { @MainActor [weak self] in
                await self?.createHostedWebNotification(
                    identifier: identifier,
                    title: title,
                    body: notificationBody,
                    isSilent: isSilent,
                    origin: origin,
                    documentIdentifier: documentIdentifier
                )
            }
        case "close":
            guard let identifier = body["identifier"] as? String,
                isValidHostedWebNotificationIdentifier(identifier)
            else { return }
            let systemIdentifier = hostedSystemIdentifier(for: identifier)
            hostedNotificationIdentifiers.remove(systemIdentifier)
            Task { @MainActor [weak hostedNotificationCenter] in
                await hostedNotificationCenter?.remove(identifier: systemIdentifier)
            }
        default:
            return
        }
    }

    func removeHostedWebNotifications() {
        guard let hostedNotificationCenter else {
            hostedNotificationIdentifiers.removeAll()
            return
        }
        let identifiers = hostedNotificationIdentifiers
        hostedNotificationIdentifiers.removeAll()
        Task { @MainActor in
            for identifier in identifiers {
                await hostedNotificationCenter.remove(identifier: identifier)
            }
        }
    }

    func beginHostedWebNotificationNavigation() {
        removeHostedWebNotifications()
        hostedNotificationDocumentIdentifier = UUID().uuidString
    }

    private func resolveHostedNotificationPermission(
        requestID: String,
        origin: BrowserSiteOrigin,
        hasUserActivation: Bool,
        documentIdentifier: String,
        frame: WKFrameInfo
    ) async {
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        let decision = permissionCenter.decision(
            for: .notifications,
            origin: origin,
            in: spaceID
        )
        switch BrowserHostedWebNotificationPermissionRequestPolicy.action(
            for: decision,
            hasUserActivation: hasUserActivation
        ) {
        case .respondDenied:
            sendHostedNotificationPermissionResponse(
                requestID: requestID,
                permission: "denied",
                documentIdentifier: documentIdentifier,
                origin: origin,
                frame: frame
            )
        case .resolveSystemAuthorization:
            await sendHostedNotificationPermission(
                requestID: requestID,
                origin: origin,
                requestsSystemAuthorization: hasUserActivation,
                documentIdentifier: documentIdentifier,
                frame: frame
            )
        case .respondDefault:
            sendHostedNotificationPermissionResponse(
                requestID: requestID,
                permission: "default",
                documentIdentifier: documentIdentifier,
                origin: origin,
                frame: frame
            )
        case .promptForSitePermission:
            let response = await dialogPresenter.presentHostedNotificationPermission(
                origin: origin,
                spaceName: spaceName
            )
            guard
                isCurrentHostedNotificationDocument(
                    documentIdentifier,
                    origin: origin
                )
            else { return }
            switch response {
            case .denyPersistently:
                permissionCenter.setDecision(
                    .denyPersistently,
                    for: .notifications,
                    origin: origin,
                    in: spaceID
                )
                sendHostedNotificationPermissionResponse(
                    requestID: requestID,
                    permission: "denied",
                    documentIdentifier: documentIdentifier,
                    origin: origin,
                    frame: frame
                )
            case .allowOnce, .grantPersistently:
                guard await authorizedForSystemNotifications(requestIfNeeded: true) else {
                    sendHostedNotificationPermissionResponse(
                        requestID: requestID,
                        permission: "denied",
                        documentIdentifier: documentIdentifier,
                        origin: origin,
                        frame: frame
                    )
                    return
                }
                guard
                    isCurrentHostedNotificationDocument(
                        documentIdentifier,
                        origin: origin
                    )
                else { return }
                permissionCenter.setDecision(
                    response == .allowOnce
                        ? .grantForSession
                        : .grantPersistently,
                    for: .notifications,
                    origin: origin,
                    in: spaceID
                )
                sendHostedNotificationPermissionResponse(
                    requestID: requestID,
                    permission: "granted",
                    documentIdentifier: documentIdentifier,
                    origin: origin,
                    frame: frame
                )
            }
        }
    }

    private func sendHostedNotificationPermission(
        requestID: String,
        origin: BrowserSiteOrigin,
        requestsSystemAuthorization: Bool,
        documentIdentifier: String,
        frame: WKFrameInfo?
    ) async {
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        let siteDecision = permissionCenter.decision(
            for: .notifications,
            origin: origin,
            in: spaceID
        )
        let permission: String
        switch siteDecision {
        case .denyForSession, .denyPersistently:
            permission = "denied"
        case .ask:
            permission = "default"
        case .grantForSession, .grantPersistently:
            guard let hostedNotificationCenter else {
                permission = "denied"
                break
            }
            if requestsSystemAuthorization {
                permission =
                    await authorizedForSystemNotifications(
                        requestIfNeeded: true
                    )
                    ? "granted" : "denied"
            } else {
                switch await hostedNotificationCenter.currentAuthorization() {
                case .authorized:
                    permission = "granted"
                case .denied:
                    permission = "denied"
                case .notDetermined:
                    permission = "default"
                }
            }
        }
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        sendHostedNotificationPermissionResponse(
            requestID: requestID,
            permission: permission,
            documentIdentifier: documentIdentifier,
            origin: origin,
            frame: frame
        )
    }

    private func createHostedWebNotification(
        identifier: String,
        title: String,
        body: String,
        isSilent: Bool,
        origin: BrowserSiteOrigin,
        documentIdentifier: String
    ) async {
        let siteDecision = permissionCenter.decision(
            for: .notifications,
            origin: origin,
            in: spaceID
        )
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            ),
            siteDecision == .grantForSession
                || siteDecision == .grantPersistently,
            let hostedNotificationCenter,
            await hostedNotificationCenter.currentAuthorization() == .authorized
        else {
            sendHostedNotificationEvent(
                identifier: identifier,
                event: "error",
                documentIdentifier: documentIdentifier,
                origin: origin
            )
            return
        }

        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        let systemIdentifier =
            "\(documentIdentifier).\(identifier)"
        do {
            try await hostedNotificationCenter.add(
                BrowserHostedWebNotificationDelivery(
                    identifier: systemIdentifier,
                    title: String(title.prefix(200)),
                    body: String(body.prefix(1_000)),
                    origin: origin,
                    isSilent: isSilent
                )
            ) { [weak self] event in
                guard let self,
                    isCurrentHostedNotificationDocument(
                        documentIdentifier,
                        origin: origin
                    )
                else { return }
                switch event {
                case .clicked:
                    hostedNotificationIdentifiers.remove(systemIdentifier)
                    host?.activateNotificationSourcePage(self)
                    NSApp.activate()
                    sendHostedNotificationEvent(
                        identifier: identifier,
                        event: "click",
                        documentIdentifier: documentIdentifier,
                        origin: origin
                    )
                }
            }
            guard
                isCurrentHostedNotificationDocument(
                    documentIdentifier,
                    origin: origin
                )
            else {
                await hostedNotificationCenter.remove(identifier: systemIdentifier)
                return
            }
            hostedNotificationIdentifiers.insert(systemIdentifier)
            sendHostedNotificationEvent(
                identifier: identifier,
                event: "show",
                documentIdentifier: documentIdentifier,
                origin: origin
            )
        } catch {
            sendHostedNotificationEvent(
                identifier: identifier,
                event: "error",
                documentIdentifier: documentIdentifier,
                origin: origin
            )
        }
    }

    private func authorizedForSystemNotifications(
        requestIfNeeded: Bool
    ) async -> Bool {
        guard let hostedNotificationCenter else { return false }
        switch await hostedNotificationCenter.currentAuthorization() {
        case .authorized:
            return true
        case .denied:
            await recoverNotificationSystemAuthorization()
            return await hostedNotificationCenter.currentAuthorization()
                == .authorized
        case .notDetermined:
            guard requestIfNeeded else { return false }
            return await hostedNotificationCenter.requestAuthorization() == .authorized
        }
    }

    private func hasActiveUserGesture(in frame: WKFrameInfo) async -> Bool {
        let result = try? await webView.callAsyncJavaScript(
            "return navigator.userActivation?.isActive === true;",
            arguments: [:],
            in: frame,
            contentWorld: .page
        )
        return result as? Bool ?? false
    }

    private func hostedSystemIdentifier(for identifier: String) -> String {
        "\(hostedNotificationDocumentIdentifier).\(identifier)"
    }

    private func isValidHostedWebNotificationIdentifier(
        _ identifier: String
    ) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 128
    }

    private func sendHostedNotificationPermissionResponse(
        requestID: String,
        permission: String,
        documentIdentifier: String,
        origin: BrowserSiteOrigin,
        frame: WKFrameInfo?
    ) {
        sendHostedNotificationMessage(
            [
                "type": "permission",
                "requestID": requestID,
                "permission": permission,
            ],
            documentIdentifier: documentIdentifier,
            origin: origin,
            frame: frame
        )
    }

    private func sendHostedNotificationEvent(
        identifier: String,
        event: String,
        documentIdentifier: String,
        origin: BrowserSiteOrigin
    ) {
        sendHostedNotificationMessage(
            [
                "type": "event",
                "identifier": identifier,
                "event": event,
            ],
            documentIdentifier: documentIdentifier,
            origin: origin,
            frame: nil
        )
    }

    private func sendHostedNotificationMessage(
        _ message: [String: Any],
        documentIdentifier: String,
        origin: BrowserSiteOrigin,
        frame: WKFrameInfo?
    ) {
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        Task { @MainActor [weak self, weak webView] in
            guard let self,
                isCurrentHostedNotificationDocument(
                    documentIdentifier,
                    origin: origin
                )
            else { return }
            _ = try? await webView?.callAsyncJavaScript(
                "globalThis.__crestHostedNotificationBridge?.receive(message);",
                arguments: ["message": message],
                in: frame,
                contentWorld: .page
            )
        }
    }

    private func isCurrentHostedNotificationDocument(
        _ documentIdentifier: String,
        origin: BrowserSiteOrigin
    ) -> Bool {
        guard documentIdentifier == hostedNotificationDocumentIdentifier,
            let currentURL = webView.url ?? displayURL,
            let currentOrigin = BrowserSiteOrigin(url: currentURL)
        else { return false }
        return currentOrigin == origin
    }
}
