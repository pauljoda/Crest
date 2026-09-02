import AppKit
import CoreGraphics
import Foundation
import WebKit
import os

enum BrowserExtensionSystemIdleState: String, Equatable, Sendable {
    case active
    case idle
    case locked
}

@MainActor
final class BrowserExtensionIdleWatch {
    private let stateProvider: (TimeInterval) -> BrowserExtensionSystemIdleState
    private let publish: ([String: Any]) -> Void
    private var detectionIntervalInSeconds: TimeInterval = 60
    private var lastPublishedState: BrowserExtensionSystemIdleState?
    private var pollingTask: Task<Void, Never>?

    init(
        stateProvider:
            @escaping (TimeInterval) -> BrowserExtensionSystemIdleState,
        publish: @escaping ([String: Any]) -> Void
    ) {
        self.stateProvider = stateProvider
        self.publish = publish
    }

    func configure(_ message: Any) throws {
        guard
            let request = message as? [String: Any],
            request["api"] as? String == "idle.watch",
            let interval = request["detectionIntervalInSeconds"]
                as? NSNumber,
            interval.doubleValue.isFinite,
            interval.doubleValue >= 0
        else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        detectionIntervalInSeconds = interval.doubleValue
        publishCurrentState()
        startPolling()
    }

    func publishCurrentState() {
        let state = stateProvider(detectionIntervalInSeconds)
        guard state != lastPublishedState else { return }
        lastPublishedState = state
        publish(["state": state.rawValue])
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.publishCurrentState()
            }
        }
    }
}

@MainActor
final class BrowserExtensionCapabilityBrokerConnection {
    private enum Watch {
        case idle(BrowserExtensionIdleWatch)
        case notifications(Task<Void, Never>)
    }

    private let authorization: BrowserExtensionNativeMessagingAuthorization
    private let notificationService: (any BrowserExtensionNotificationHandling)?
    private let idleStateProvider: (TimeInterval) -> BrowserExtensionSystemIdleState
    private let publish: ([String: Any]) -> Void
    private let webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry
    private var watch: Watch?
    private var webpageMenuClickObserver: UUID?

    init(
        authorization: BrowserExtensionNativeMessagingAuthorization,
        notificationService:
            (any BrowserExtensionNotificationHandling)?,
        idleStateProvider:
            @escaping (TimeInterval) -> BrowserExtensionSystemIdleState,
        webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry,
        publish: @escaping ([String: Any]) -> Void
    ) {
        self.authorization = authorization
        self.notificationService = notificationService
        self.idleStateProvider = idleStateProvider
        self.webpageMenuRegistry = webpageMenuRegistry
        self.publish = publish
    }

    func receive(_ message: Any) throws {
        guard
            let request = message as? [String: Any],
            let api = request["api"] as? String
        else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        switch api {
        case "contextMenus.replace":
            try replaceContextMenus(request)
        case "contextMenus.ready":
            try publishContextMenuReadyState()
        case "runtime.onInstalled.ack":
            try acknowledgeContextMenuLifecycle(request)
        case "idle.watch":
            try configureIdleWatch(request)
        case "notifications.watch":
            try configureNotificationWatch()
        default:
            throw BrowserExtensionCapabilityBrokerError.unsupportedAPI(api)
        }
    }

    func stop() {
        if let clientID = authorization.clientID,
            let webpageMenuClickObserver
        {
            webpageMenuRegistry.removeClickObserver(
                webpageMenuClickObserver,
                for: clientID
            )
        }
        webpageMenuClickObserver = nil
        switch watch {
        case .idle(let watch):
            watch.stop()
        case .notifications(let task):
            task.cancel()
        case nil:
            break
        }
        watch = nil
    }

    private func replaceContextMenus(_ request: [String: Any]) throws {
        guard authorization.grants("contextMenus") else {
            throw BrowserExtensionCapabilityBrokerError.permissionDenied(
                "contextMenus"
            )
        }
        guard let clientID = authorization.clientID else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        try webpageMenuRegistry.replaceDefinitions(
            message: request,
            for: clientID
        )
        observeContextMenuClicks(for: clientID)
    }

    private func observeContextMenuClicks(
        for clientID: BrowserExtensionServiceClientID
    ) {
        if webpageMenuClickObserver == nil {
            webpageMenuClickObserver = webpageMenuRegistry.observeClicks(
                for: clientID,
                publish: publish
            )
        }
    }

    private func publishContextMenuReadyState() throws {
        let clientID = try contextMenuClientID()
        if let message = webpageMenuRegistry.restorationMessage(for: clientID) {
            publish(message)
        }
        observeContextMenuClicks(for: clientID)
        if let message =
            webpageMenuRegistry
            .pendingInstallLifecycleMessage(for: clientID)
        {
            publish(message)
        }
    }

    private func acknowledgeContextMenuLifecycle(
        _ request: [String: Any]
    ) throws {
        let clientID = try contextMenuClientID()
        guard let eventID = request["eventID"] as? String,
            webpageMenuRegistry.acknowledgeInstallLifecycle(
                eventID: eventID,
                for: clientID
            )
        else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
    }

    private func contextMenuClientID() throws
        -> BrowserExtensionServiceClientID
    {
        guard authorization.grants("contextMenus") else {
            throw BrowserExtensionCapabilityBrokerError.permissionDenied(
                "contextMenus"
            )
        }
        guard let clientID = authorization.clientID else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        return clientID
    }

    private func configureIdleWatch(_ request: [String: Any]) throws {
        guard authorization.grants("idle") else {
            throw BrowserExtensionCapabilityBrokerError.permissionDenied(
                "idle"
            )
        }
        let idleWatch: BrowserExtensionIdleWatch
        switch watch {
        case .idle(let existing):
            idleWatch = existing
        case .notifications:
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        case nil:
            idleWatch = BrowserExtensionIdleWatch(
                stateProvider: idleStateProvider,
                publish: publish
            )
            watch = .idle(idleWatch)
        }
        try idleWatch.configure(request)
    }

    private func configureNotificationWatch() throws {
        guard authorization.grants("notifications") else {
            throw BrowserExtensionCapabilityBrokerError.permissionDenied(
                "notifications"
            )
        }
        guard let client = authorization.clientID else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        guard let notificationService else {
            throw BrowserExtensionCapabilityBrokerError.unsupportedAPI(
                "notifications"
            )
        }
        switch watch {
        case .notifications:
            return
        case .idle:
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        case nil:
            break
        }
        let events = notificationService.events(for: client)
        let task = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.publish(Self.message(for: event))
            }
        }
        watch = .notifications(task)
    }

    private static func message(
        for event: BrowserExtensionNotificationEvent
    ) -> [String: Any] {
        var message: [String: Any] = [
            "api": "notifications.event",
            "notificationIdentifier":
                event.identity.notificationIdentifier,
        ]
        switch event.kind {
        case .clicked:
            message["kind"] = "clicked"
        case .buttonClicked(let index):
            message["kind"] = "buttonClicked"
            message["buttonIndex"] = index
        case .dismissed(let byUser):
            message["kind"] = "closed"
            message["byUser"] = byUser
        }
        return message
    }
}

@MainActor
private final class BrowserExtensionSystemIdleStateMonitor: NSObject {
    private let notificationCenter: NotificationCenter
    private var sessionIsActive = true

    init(
        notificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter
    ) {
        self.notificationCenter = notificationCenter
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    func state(
        detectionIntervalInSeconds: TimeInterval
    ) -> BrowserExtensionSystemIdleState {
        guard sessionIsActive else { return .locked }
        guard
            let anyInputEvent = CGEventType(rawValue: UInt32.max)
        else {
            return .active
        }
        let secondsSinceLastInput =
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: anyInputEvent
            )
        return secondsSinceLastInput >= detectionIntervalInSeconds
            ? .idle
            : .active
    }

    @objc private func sessionDidResignActive() {
        sessionIsActive = false
    }

    @objc private func sessionDidBecomeActive() {
        sessionIsActive = true
    }
}

@MainActor
final class BrowserNativeMessagingService:
    BrowserExtensionNativeMessagingHandling
{
    private static let log = Logger(
        subsystem: "com.pauldavis.crest",
        category: "extension-native-messaging"
    )

    static let capabilityBrokerIdentifier =
        BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier

    let capability: BrowserExtensionNativeMessagingCapability
    private let resolver: BrowserNativeMessagingHostManifestResolver
    private let replyTimeout: Duration
    private let notificationService: (any BrowserExtensionNotificationHandling)?
    private let idleStateProvider: (TimeInterval) -> BrowserExtensionSystemIdleState
    let webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry
    private var connections: [ObjectIdentifier: BrowserNativeMessagingPersistentConnection] = [:]
    private var capabilityConnections: [ObjectIdentifier: BrowserExtensionCapabilityBrokerConnection] = [:]

    init(
        capability: BrowserExtensionNativeMessagingCapability,
        resolver: BrowserNativeMessagingHostManifestResolver,
        replyTimeout: Duration = .seconds(30),
        notificationService:
            (any BrowserExtensionNotificationHandling)? = nil,
        webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry =
            BrowserExtensionWebpageMenuRegistry(),
        idleStateProvider:
            ((TimeInterval) -> BrowserExtensionSystemIdleState)? = nil
    ) {
        self.capability = capability
        self.resolver = resolver
        self.replyTimeout = replyTimeout
        self.notificationService = notificationService
        self.webpageMenuRegistry = webpageMenuRegistry
        if let idleStateProvider {
            self.idleStateProvider = idleStateProvider
        } else {
            let monitor = BrowserExtensionSystemIdleStateMonitor()
            self.idleStateProvider = { interval in
                monitor.state(detectionIntervalInSeconds: interval)
            }
        }
    }

    static func production(
        webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry =
            BrowserExtensionWebpageMenuRegistry()
    ) -> BrowserNativeMessagingService {
        let notificationCenter = BrowserExtensionNotificationSystemCenter(
            center: .current()
        )
        return BrowserNativeMessagingService(
            capability:
                BrowserPlatformExtensionNativeMessagingCapability.currentBuild,
            resolver: .production(),
            notificationService: BrowserExtensionNotificationService(
                center: notificationCenter
            ),
            webpageMenuRegistry: webpageMenuRegistry
        )
    }

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity?,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        // Two capabilities share this entry point. `capability` answers whether
        // Crest may launch an external native host process, which App Sandbox
        // forbids. The capability broker is Crest's own in-process emulation
        // transport: it spawns nothing, so it is answered before that guard and
        // works in every build, sandboxed App Store one included.
        if applicationIdentifier == Self.capabilityBrokerIdentifier {
            guard authorization.allowsInternalCapabilityBroker else {
                replyHandler(
                    nil,
                    BrowserExtensionCapabilityBrokerError.permissionDenied(
                        "internalCapabilityBroker"
                    )
                )
                return
            }
            Task { @MainActor in
                do {
                    replyHandler(
                        try await capabilityResponse(
                            for: message,
                            authorization: authorization
                        ),
                        nil
                    )
                } catch {
                    replyHandler(nil, error)
                }
            }
            return
        }
        guard capability == .available else {
            replyHandler(nil, BrowserExtensionNativeMessagingError.unavailable)
            return
        }
        guard authorization.grants("nativeMessaging") else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.permissionDenied(
                    "nativeMessaging"
                )
            )
            return
        }
        guard let extensionIdentity else {
            replyHandler(
                nil,
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return
        }
        do {
            let host = try resolver.resolve(
                hostName: applicationIdentifier ?? "",
                extensionIdentity: extensionIdentity
            )
            var connection: BrowserNativeMessagingProcessConnection?
            // One reply completes this exchange, so bound the wait: a host that
            // never answers would otherwise hold its child process and pipes
            // for as long as the browser runs.
            connection = try BrowserNativeMessagingProcessConnection(
                host: host,
                replyTimeout: replyTimeout,
                receive: { value in
                    guard connection != nil else { return }
                    replyHandler(value, nil)
                    let completedConnection = connection
                    connection = nil
                    completedConnection?.disconnect()
                },
                disconnect: { error in
                    guard connection != nil else { return }
                    replyHandler(nil, error)
                    connection = nil
                }
            )
            try connection?.send(message)
        } catch {
            replyHandler(nil, error)
        }
    }

    func connect(
        port: WKWebExtension.MessagePort,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity?,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // As in `sendMessage`, the in-process capability broker is answered
        // before the external-host capability guard. A sandboxed build cannot
        // launch a host, but it can still serve its own emulation transport,
        // and gating it here made every brokered API fail and reconnect
        // forever in the App Store build.
        if port.applicationIdentifier == Self.capabilityBrokerIdentifier {
            guard authorization.allowsInternalCapabilityBroker else {
                completionHandler(
                    BrowserExtensionCapabilityBrokerError.permissionDenied(
                        "internalCapabilityBroker"
                    )
                )
                return
            }
            let key = ObjectIdentifier(port)
            let connection = BrowserExtensionCapabilityBrokerConnection(
                authorization: authorization,
                notificationService: notificationService,
                idleStateProvider: idleStateProvider,
                webpageMenuRegistry: webpageMenuRegistry,
                publish: { [weak port] message in
                    port?.sendMessage(message, completionHandler: nil)
                }
            )
            capabilityConnections[key] = connection
            port.messageHandler = { [weak self] message, error in
                guard
                    let self,
                    let connection = self.capabilityConnections[key]
                else {
                    return
                }
                if error != nil {
                    self.removeCapabilityConnection(for: key)
                    if !port.isDisconnected {
                        port.disconnect()
                    }
                    return
                }
                do {
                    try connection.receive(message ?? NSNull())
                } catch {
                    let api =
                        (message as? [String: Any])?["api"] as? String
                        ?? "unknown"
                    Self.log.error(
                        "capability broker rejected \(api, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                    self.removeCapabilityConnection(for: key)
                    if !port.isDisconnected {
                        port.disconnect()
                    }
                }
            }
            port.disconnectHandler = { [weak self] _ in
                self?.removeCapabilityConnection(for: key)
            }
            completionHandler(nil)
            return
        }
        guard capability == .available else {
            completionHandler(
                BrowserExtensionNativeMessagingError.unavailable
            )
            return
        }
        guard authorization.grants("nativeMessaging") else {
            completionHandler(
                BrowserExtensionCapabilityBrokerError.permissionDenied(
                    "nativeMessaging"
                )
            )
            return
        }
        guard let extensionIdentity else {
            completionHandler(
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return
        }
        do {
            let host = try resolver.resolve(
                hostName: port.applicationIdentifier ?? "",
                extensionIdentity: extensionIdentity
            )
            let key = ObjectIdentifier(port)
            // A persistent port may idle for as long as the extension keeps it
            // open, and its disconnect handler already bounds the child, so
            // this direction stays untimed.
            let connection = try BrowserNativeMessagingProcessConnection(
                host: host,
                receive: { [weak self] message in
                    self?.connections[key]?.port.sendMessage(
                        message,
                        completionHandler: nil
                    )
                },
                disconnect: { [weak self] error in
                    if let persistentConnection = self?.connections
                        .removeValue(forKey: key),
                        !persistentConnection.port.isDisconnected
                    {
                        persistentConnection.port.disconnect()
                    }
                    _ = error
                }
            )
            connections[key] = BrowserNativeMessagingPersistentConnection(
                port: port,
                process: connection
            )
            port.messageHandler = { [weak self] message, error in
                guard let connection = self?.connections[key]?.process else {
                    return
                }
                if let error {
                    connection.disconnect(error: error)
                    return
                }
                do {
                    try connection.send(message ?? NSNull())
                } catch {
                    connection.disconnect(error: error)
                }
            }
            port.disconnectHandler = { [weak self] _ in
                self?.connections.removeValue(forKey: key)?.process.disconnect()
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        sendMessage(
            message,
            applicationIdentifier: applicationIdentifier,
            extensionIdentity: extensionIdentity,
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["nativeMessaging"]
            ),
            replyHandler: replyHandler
        )
    }

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionID: BrowserChromeExtensionID,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        sendMessage(
            message,
            applicationIdentifier: applicationIdentifier,
            extensionIdentity: .chromeWebStore(extensionID),
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["nativeMessaging"]
            ),
            replyHandler: replyHandler
        )
    }

    private func capabilityResponse(
        for message: Any,
        authorization: BrowserExtensionNativeMessagingAuthorization
    ) async throws -> Any {
        guard
            let request = message as? [String: Any],
            let api = request["api"] as? String
        else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        guard authorization.allowsInternalCapabilityBroker else {
            throw BrowserExtensionCapabilityBrokerError.permissionDenied(
                "internalCapabilityBroker"
            )
        }
        switch api {
        case "idle.queryState":
            guard authorization.grants("idle") else {
                throw BrowserExtensionCapabilityBrokerError.permissionDenied(
                    "idle"
                )
            }
            guard
                let interval = request["detectionIntervalInSeconds"]
                    as? NSNumber,
                interval.doubleValue.isFinite,
                interval.doubleValue >= 0
            else {
                throw BrowserExtensionCapabilityBrokerError.invalidRequest
            }
            return [
                "state": idleStateProvider(interval.doubleValue).rawValue
            ]
        case "notifications.create":
            let (service, client) = try notificationCapability(
                authorization: authorization
            )
            let notificationRequest = try notificationRequest(from: request)
            let outcome = await service.post(
                notificationRequest,
                from: client
            )
            switch outcome {
            case .presented:
                return [
                    "notificationIdentifier": notificationRequest.identifier,
                    "presented": true,
                ]
            case .authorizationDenied:
                return [
                    "notificationIdentifier": notificationRequest.identifier,
                    "presented": false,
                ]
            case .rejected(let description):
                throw BrowserExtensionCapabilityBrokerError.serviceFailure(
                    description
                )
            }
        case "notifications.clear":
            let (service, client) = try notificationCapability(
                authorization: authorization
            )
            let notificationIdentifier = try notificationIdentifier(
                from: request
            )
            return [
                "cleared": await service.clear(
                    notificationIdentifier: notificationIdentifier,
                    from: client
                )
            ]
        case "notifications.getAll":
            let (service, client) = try notificationCapability(
                authorization: authorization
            )
            return [
                "notificationIdentifiers":
                    await service.presentedNotificationIdentifiers(
                        for: client
                    )
            ]
        case "notifications.getPermissionLevel":
            let (service, _) = try notificationCapability(
                authorization: authorization
            )
            return [
                "level": await service.currentAuthorization() == .authorized
                    ? "granted"
                    : "denied"
            ]
        case "notifications.update":
            let (service, client) = try notificationCapability(
                authorization: authorization
            )
            let outcome = await service.update(
                try notificationUpdate(from: request),
                from: client
            )
            switch outcome {
            case .updated:
                return ["updated": true]
            case .unknownNotification, .authorizationDenied:
                return ["updated": false]
            case .rejected(let description):
                throw BrowserExtensionCapabilityBrokerError.serviceFailure(
                    description
                )
            }
        default:
            throw BrowserExtensionCapabilityBrokerError.unsupportedAPI(api)
        }
    }

    private func notificationRequest(
        from request: [String: Any]
    ) throws -> BrowserExtensionNotificationRequest {
        let notificationIdentifier = try notificationIdentifier(from: request)
        guard
            let title = request["title"] as? String,
            let notificationMessage = request["message"] as? String,
            let buttonTitles = request["buttonTitles"] as? [String]
        else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        return BrowserExtensionNotificationRequest(
            identifier: notificationIdentifier,
            title: title,
            message: notificationMessage,
            buttonTitles: buttonTitles
        )
    }

    /// Reads the fields a `chrome.notifications.update` call actually supplied.
    ///
    /// Unlike `create`, every content field is optional: Chrome's `update`
    /// edits only what it was given, so a field that is absent — or explicitly
    /// null — is reported as "keep" rather than defaulted to an empty value
    /// that would blank the presented notification. A field that is present
    /// with the wrong type is still a malformed request.
    private func notificationUpdate(
        from request: [String: Any]
    ) throws -> BrowserExtensionNotificationUpdate {
        let notificationIdentifier = try notificationIdentifier(from: request)
        return BrowserExtensionNotificationUpdate(
            identifier: notificationIdentifier,
            title: try optionalString(named: "title", in: request),
            message: try optionalString(named: "message", in: request),
            buttonTitles: try optionalStringArray(
                named: "buttonTitles",
                in: request
            )
        )
    }

    private func optionalString(
        named key: String,
        in request: [String: Any]
    ) throws -> String? {
        guard let value = request[key], !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        return string
    }

    private func optionalStringArray(
        named key: String,
        in request: [String: Any]
    ) throws -> [String]? {
        guard let value = request[key], !(value is NSNull) else { return nil }
        guard let strings = value as? [String] else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        return strings
    }

    private func notificationIdentifier(
        from request: [String: Any]
    ) throws -> String {
        guard
            let notificationIdentifier =
                request["notificationIdentifier"] as? String,
            !notificationIdentifier.isEmpty
        else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        return notificationIdentifier
    }

    private func notificationCapability(
        authorization: BrowserExtensionNativeMessagingAuthorization
    ) throws -> (
        any BrowserExtensionNotificationHandling,
        BrowserExtensionServiceClientID
    ) {
        guard authorization.grants("notifications") else {
            throw BrowserExtensionCapabilityBrokerError.permissionDenied(
                "notifications"
            )
        }
        guard let client = authorization.clientID else {
            throw BrowserExtensionCapabilityBrokerError.invalidRequest
        }
        guard let notificationService else {
            throw BrowserExtensionCapabilityBrokerError.unsupportedAPI(
                "notifications"
            )
        }
        return (notificationService, client)
    }

    private func removeCapabilityConnection(for key: ObjectIdentifier) {
        capabilityConnections.removeValue(forKey: key)?.stop()
    }
}
