import Foundation
import WebKit

/// Owns Crest's Core Location-backed Geolocation API. Both browser surfaces
/// share this coordinator so site consent, system authorization, document
/// lifetime, and web-standard behavior cannot drift.
@MainActor
final class BrowserGeolocationCoordinator {
    typealias Prompt =
        @MainActor (
            _ origin: BrowserSiteOrigin,
            _ topLevelURL: URL?,
            _ spaceName: String
        ) async -> BrowserSitePermissionPromptResponse
    typealias RecoverSystemAuthorization = @MainActor () async -> Void

    private let webView: WKWebView
    private let permissionCenter: BrowserSitePermissionCenter
    private let service: any BrowserGeolocationServicing
    private let spaceID: SpaceID
    private let spaceName: String
    private let prompt: Prompt
    private let recoverSystemAuthorization: RecoverSystemAuthorization

    private var documentIdentifier = UUID().uuidString
    private var activeIdentifiers: Set<String> = []
    private var requestTasks: [String: Task<Void, Never>] = [:]

    init(
        webView: WKWebView,
        permissionCenter: BrowserSitePermissionCenter,
        service: any BrowserGeolocationServicing,
        spaceID: SpaceID,
        spaceName: String,
        prompt: @escaping Prompt,
        recoverSystemAuthorization: @escaping RecoverSystemAuthorization
    ) {
        self.webView = webView
        self.permissionCenter = permissionCenter
        self.service = service
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.prompt = prompt
        self.recoverSystemAuthorization = recoverSystemAuthorization
    }

    func receive(_ message: WKScriptMessage) {
        guard message.webView === webView,
            let requestURL = message.frameInfo.request.url,
            let origin = BrowserSiteOrigin(url: requestURL),
            BrowserGeolocationOriginPolicy.allows(origin),
            let body = message.body as? [String: Any],
            (body["version"] as? Int) == 1,
            let action = body["action"] as? String
        else { return }

        let messageDocumentIdentifier = documentIdentifier
        switch action {
        case "queryPermission":
            sendPermission(
                origin: origin,
                documentIdentifier: messageDocumentIdentifier,
                frame: message.frameInfo
            )
        case "getCurrentPosition", "watchPosition":
            guard let identifier = body["identifier"] as? String,
                Self.isValidIdentifier(identifier)
            else { return }
            beginRequest(
                identifier: identifier,
                watchesPosition: action == "watchPosition",
                options: Self.options(from: body["options"]),
                origin: origin,
                documentIdentifier: messageDocumentIdentifier,
                frame: message.frameInfo
            )
        case "cancel":
            guard let identifier = body["identifier"] as? String,
                Self.isValidIdentifier(identifier)
            else { return }
            cancel(nativeIdentifier: "\(messageDocumentIdentifier).\(identifier)")
        case "cancelAll":
            cancelAll()
        default:
            return
        }
    }

    func synchronizeMainFramePermission() {
        guard let currentURL = webView.url,
            let origin = BrowserSiteOrigin(url: currentURL)
        else { return }
        sendPermission(
            origin: origin,
            documentIdentifier: documentIdentifier,
            frame: nil
        )
    }

    func beginNavigation() {
        cancelAll()
        documentIdentifier = UUID().uuidString
    }

    func cancelAll() {
        for task in requestTasks.values {
            task.cancel()
        }
        requestTasks.removeAll()
        for identifier in activeIdentifiers {
            service.cancel(identifier: identifier)
        }
        activeIdentifiers.removeAll()
        service.cancelAll()
    }

    private func beginRequest(
        identifier: String,
        watchesPosition: Bool,
        options: BrowserGeolocationRequestOptions,
        origin: BrowserSiteOrigin,
        documentIdentifier: String,
        frame: WKFrameInfo
    ) {
        let nativeIdentifier = "\(documentIdentifier).\(identifier)"
        cancel(nativeIdentifier: nativeIdentifier)
        requestTasks[nativeIdentifier] = Task { @MainActor [weak self] in
            guard let self else { return }
            let isAuthorized = await authorize(
                origin: origin,
                documentIdentifier: documentIdentifier
            )
            guard isAuthorized,
                !Task.isCancelled,
                isCurrentDocument(documentIdentifier)
            else {
                sendPermission(
                    origin: origin,
                    documentIdentifier: documentIdentifier,
                    frame: frame
                )
                sendError(
                    .permissionDenied,
                    identifier: identifier,
                    documentIdentifier: documentIdentifier,
                    frame: frame
                )
                requestTasks.removeValue(forKey: nativeIdentifier)
                return
            }

            sendPermission(
                origin: origin,
                documentIdentifier: documentIdentifier,
                frame: frame
            )
            activeIdentifiers.insert(nativeIdentifier)
            let receive: @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void = {
                [weak self] result in
                guard let self else { return }
                if !watchesPosition {
                    activeIdentifiers.remove(nativeIdentifier)
                }
                guard isCurrentDocument(documentIdentifier) else { return }
                switch result {
                case .success(let position):
                    sendPosition(
                        position,
                        identifier: identifier,
                        documentIdentifier: documentIdentifier,
                        frame: frame
                    )
                case .failure(let error):
                    sendError(
                        error,
                        identifier: identifier,
                        documentIdentifier: documentIdentifier,
                        frame: frame
                    )
                }
            }
            if watchesPosition {
                service.startWatchingPosition(
                    identifier: nativeIdentifier,
                    options: options,
                    receive: receive
                )
            } else {
                service.requestCurrentPosition(
                    identifier: nativeIdentifier,
                    options: options,
                    receive: receive
                )
            }
            requestTasks.removeValue(forKey: nativeIdentifier)
        }
    }

    private func authorize(
        origin: BrowserSiteOrigin,
        documentIdentifier: String
    ) async -> Bool {
        var decisionToPersist: BrowserSitePermissionDecision?
        switch permissionCenter.decision(
            for: .location,
            origin: origin,
            in: spaceID
        ) {
        case .denyForSession, .denyPersistently:
            return false
        case .grantForSession, .grantPersistently:
            break
        case .ask:
            let response = await prompt(origin, webView.url, spaceName)
            guard isCurrentDocument(documentIdentifier) else { return false }
            switch response {
            case .allowOnce:
                break
            case .grantPersistently:
                decisionToPersist = .grantPersistently
            case .denyPersistently:
                permissionCenter.setDecision(
                    .denyPersistently,
                    for: .location,
                    origin: origin,
                    in: spaceID
                )
                return false
            }
        }

        guard isCurrentDocument(documentIdentifier) else { return false }
        let isSystemAuthorized: Bool
        switch service.currentAuthorization() {
        case .authorized:
            isSystemAuthorized = true
        case .denied:
            await recoverSystemAuthorization()
            guard isCurrentDocument(documentIdentifier) else { return false }
            isSystemAuthorized = service.currentAuthorization() == .authorized
        case .notDetermined:
            isSystemAuthorized =
                await service.requestAuthorization() == .authorized
        }
        guard isSystemAuthorized,
            isCurrentDocument(documentIdentifier)
        else { return false }
        if let decisionToPersist {
            permissionCenter.setDecision(
                decisionToPersist,
                for: .location,
                origin: origin,
                in: spaceID
            )
        }
        return true
    }

    private func sendPermission(
        origin: BrowserSiteOrigin,
        documentIdentifier: String,
        frame: WKFrameInfo?
    ) {
        let state: String
        switch permissionCenter.decision(
            for: .location,
            origin: origin,
            in: spaceID
        ) {
        case .ask:
            state = "prompt"
        case .denyForSession, .denyPersistently:
            state = "denied"
        case .grantForSession, .grantPersistently:
            switch service.currentAuthorization() {
            case .authorized:
                state = "granted"
            case .denied:
                state = "denied"
            case .notDetermined:
                state = "prompt"
            }
        }
        send(
            ["type": "permission", "state": state],
            documentIdentifier: documentIdentifier,
            frame: frame
        )
    }

    private func sendPosition(
        _ position: BrowserGeolocationPosition,
        identifier: String,
        documentIdentifier: String,
        frame: WKFrameInfo
    ) {
        send(
            [
                "type": "position",
                "identifier": identifier,
                "coords": [
                    "latitude": position.latitude,
                    "longitude": position.longitude,
                    "accuracy": position.accuracy,
                    "altitude": position.altitude.map { $0 as Any } ?? NSNull(),
                    "altitudeAccuracy": position.altitudeAccuracy.map { $0 as Any }
                        ?? NSNull(),
                    "heading": position.heading.map { $0 as Any } ?? NSNull(),
                    "speed": position.speed.map { $0 as Any } ?? NSNull(),
                ],
                "timestamp": position.timestamp,
            ],
            documentIdentifier: documentIdentifier,
            frame: frame
        )
    }

    private func sendError(
        _ error: BrowserGeolocationError,
        identifier: String,
        documentIdentifier: String,
        frame: WKFrameInfo
    ) {
        send(
            [
                "type": "error",
                "identifier": identifier,
                "code": error.code.rawValue,
                "message": error.message,
            ],
            documentIdentifier: documentIdentifier,
            frame: frame
        )
    }

    private func send(
        _ message: [String: Any],
        documentIdentifier: String,
        frame: WKFrameInfo?
    ) {
        guard isCurrentDocument(documentIdentifier) else { return }
        Task { @MainActor [weak self, weak webView] in
            guard let self, isCurrentDocument(documentIdentifier) else { return }
            _ = try? await webView?.callAsyncJavaScript(
                "globalThis.__crestGeolocationBridge?.receive(message);",
                arguments: ["message": message],
                in: frame,
                contentWorld: .page
            )
        }
    }

    private func cancel(nativeIdentifier: String) {
        requestTasks.removeValue(forKey: nativeIdentifier)?.cancel()
        activeIdentifiers.remove(nativeIdentifier)
        service.cancel(identifier: nativeIdentifier)
    }

    private func isCurrentDocument(_ identifier: String) -> Bool {
        identifier == documentIdentifier
    }

    private static func options(from value: Any?) -> BrowserGeolocationRequestOptions {
        let options = value as? [String: Any]
        let maximumAgeMilliseconds = options?["maximumAge"] as? Double ?? 0
        return BrowserGeolocationRequestOptions(
            enablesHighAccuracy: options?["enableHighAccuracy"] as? Bool ?? false,
            maximumAge: maximumAgeMilliseconds / 1_000
        )
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 128
    }
}
