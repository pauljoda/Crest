import Foundation
import Observation
import WebKit

enum BrowserExtensionDebuggerTargetAccess {
    case available(WKWebView)
    case restricted
    case closed
}

/// Owns transient, exclusive Inspector sessions. The resolver must enforce live
/// Space, URL, frame, and extension permissions; a resident page is not a grant.
/// This service is not installed in CrestApp or exposed to extensions yet.
@Observable
@MainActor
final class BrowserExtensionDebuggerSessionStore: BrowserExtensionDebuggerHandling {
    private struct Registration: Equatable {
        let spaceID: SpaceID
        let displayName: String
    }

    @MainActor
    private final class Entry {
        let id = UUID()
        let target: BrowserExtensionDebuggerTarget
        let client: BrowserExtensionServiceClientID
        weak var page: WKWebView?
        let connection: BrowserWebInspectorProtocolConnection
        let runtime: BrowserChromeDebuggerRuntime
        let screenshot: BrowserChromeDebuggerScreenshot
        let console: BrowserChromeDebuggerConsole
        let pageDomain: BrowserChromeDebuggerPage
        let network: BrowserChromeDebuggerNetwork
        let input: BrowserChromeDebuggerInput
        let targetDomain: BrowserChromeDebuggerTarget
        let unsupported = BrowserChromeDebuggerUnsupportedLog()
        var phase = BrowserExtensionDebuggerSession.Phase.attaching
        var pending: [UUID: PendingCommand] = [:]

        init(
            target: BrowserExtensionDebuggerTarget, client: BrowserExtensionServiceClientID, page: WKWebView,
            tabHost: (any BrowserExtensionDebuggerTabHosting)?
        ) {
            self.target = target
            self.client = client
            self.page = page
            connection = BrowserWebInspectorProtocolConnection(webView: page)
            runtime = BrowserChromeDebuggerRuntime(connection: connection)
            screenshot = BrowserChromeDebuggerScreenshot(connection: connection)
            console = BrowserChromeDebuggerConsole(connection: connection)
            pageDomain = BrowserChromeDebuggerPage(
                connection: connection, target: target, webView: page, tabHost: tabHost)
            network = BrowserChromeDebuggerNetwork(connection: connection)
            input = BrowserChromeDebuggerInput(webView: page)
            targetDomain = BrowserChromeDebuggerTarget(target: target, webView: page, tabHost: tabHost)
        }

        /// Every engine event reaches every translator that wants one. A single
        /// forwarding hop would silently drop a domain the moment a second one
        /// exists, which is exactly the failure a client cannot diagnose.
        func receive(_ method: String, parameters: [String: Any]) {
            runtime.receive(method, parameters: parameters)
            console.receive(method, parameters: parameters)
            pageDomain.receive(method, parameters: parameters)
            network.receive(method, parameters: parameters)
        }

        func publishEvents(_ publish: @escaping (String, [String: Any]) -> Void) {
            runtime.onEvent = publish
            console.onEvent = publish
            pageDomain.onEvent = publish
            network.onEvent = publish
        }

        func stopPublishing() {
            runtime.onEvent = nil
            console.onEvent = nil
            pageDomain.onEvent = nil
            network.onEvent = nil
            console.disable()
            network.disable()
            pageDomain.detach()
        }
    }

    private struct PendingCommand {
        let continuation: CheckedContinuation<Data, Error>
        let task: Task<Void, Never>
    }

    private(set) var sessions: [BrowserExtensionDebuggerSession] = []
    @ObservationIgnored private var registrations: [BrowserExtensionServiceClientID: Registration] = [:]
    @ObservationIgnored private var entries: [BrowserExtensionDebuggerTarget: Entry] = [:]
    @ObservationIgnored private let authorizeClient: (BrowserExtensionServiceClientID) -> Bool
    @ObservationIgnored private let resolveTarget:
        (BrowserExtensionDebuggerTarget) -> BrowserExtensionDebuggerTargetAccess
    @ObservationIgnored private let eventHub = BrowserExtensionDebuggerEventHub()
    /// Supplies the tab operations `Page.close`, `Page.bringToFront`, and
    /// `Target.closeTarget` need. Absent, those commands report unsupported
    /// rather than reaching for a tab through some other path.
    /// Tab-level operations (activate, close) the engine protocol cannot perform.
    /// Held strongly: the coordinator adapter only references the coordinator weakly.
    @ObservationIgnored var tabHost: (any BrowserExtensionDebuggerTabHosting)?

    init(
        authorizeClient: @escaping (BrowserExtensionServiceClientID) -> Bool,
        resolveTarget: @escaping (BrowserExtensionDebuggerTarget) -> BrowserExtensionDebuggerTargetAccess
    ) {
        self.authorizeClient = authorizeClient
        self.resolveTarget = resolveTarget
    }

    isolated deinit {
        shutdown()
    }

    func register(client: BrowserExtensionServiceClientID, spaceID: SpaceID, displayName: String) {
        let registration = Registration(spaceID: spaceID, displayName: displayName)
        guard registrations[client] != registration else { return }
        unregister(client: client)
        registrations[client] = registration
    }

    func unregister(client: BrowserExtensionServiceClientID) {
        registrations[client] = nil
        for entry in Array(entries.values) where entry.client == client { close(entry) }
        eventHub.remove(client: client)
    }

    func attach(
        to target: BrowserExtensionDebuggerTarget, for client: BrowserExtensionServiceClientID,
        requiredVersion: String
    ) async throws {
        try Task.checkCancellation()
        try authorize(client, target: target)
        guard BrowserExtensionDebuggerTargetPolicy.supportedProtocolVersions.contains(requiredVersion) else {
            throw BrowserExtensionDebuggerError.unsupportedVersion(requiredVersion)
        }
        guard entries[target] == nil else { throw BrowserExtensionDebuggerError.alreadyAttached }
        guard case .available(let page) = resolveTarget(target) else {
            throw BrowserExtensionDebuggerError.accessDenied
        }
        let entry = Entry(target: target, client: client, page: page, tabHost: tabHost)
        entries[target] = entry
        refreshSessions()
        entry.connection.authorizeCommand = { [weak self, weak entry] in
            guard let self, let entry else { throw BrowserExtensionDebuggerError.detachedWhileHandling }
            try self.validate(entry)
        }
        entry.connection.onEvent = { [weak self, weak entry] method, parameters in
            guard let self, let entry, (try? self.validate(entry)) != nil else { return }
            entry.receive(method, parameters: parameters)
        }
        entry.publishEvents { [weak self, weak entry] method, parameters in
            guard let self, let entry, (try? self.validate(entry)) != nil,
                let data = try? JSONSerialization.data(withJSONObject: parameters)
            else { return }
            self.eventHub.publish(
                .init(target: target, kind: .protocolMessage(method: method, parameters: data)), to: client)
        }
        do {
            try await withTaskCancellationHandler {
                try await entry.connection.connect()
                try Task.checkCancellation()
                try validate(entry)
                entry.phase = .attached
                refreshSessions()
            } onCancel: { [weak self] in
                Task { @MainActor [weak self] in self?.closeIfCurrent(target: target, id: entry.id) }
            }
        } catch {
            close(entry)
            if error as? BrowserWebInspectorProtocolError == .alreadyConnected {
                throw BrowserExtensionDebuggerError.alreadyAttached
            }
            throw error
        }
    }

    func detach(from target: BrowserExtensionDebuggerTarget, for client: BrowserExtensionServiceClientID) throws {
        try authorize(client, target: target)
        guard let entry = entries[target], entry.client == client else {
            throw BrowserExtensionDebuggerError.notAttached
        }
        // Explicit API detachment does not emit onDetach, matching Chrome.
        close(entry)
    }

    func sendCommand(
        _ command: BrowserExtensionDebuggerCommand, to target: BrowserExtensionDebuggerTarget,
        for client: BrowserExtensionServiceClientID
    ) async throws -> Data {
        try Task.checkCancellation()
        try authorize(client, target: target)
        guard let entry = entries[target], entry.client == client, entry.phase == .attached else {
            throw BrowserExtensionDebuggerError.notAttached
        }
        try validate(entry)
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = Task { @MainActor [weak self] in
                    let result: Result<Data, Error>
                    do { result = .success(try await Self.execute(command, in: entry)) } catch {
                        result = .failure(error)
                    }
                    self?.complete(result, requestID: requestID, entry: entry)
                }
                entry.pending[requestID] = .init(continuation: continuation, task: task)
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelCommand(requestID, target: target, entryID: entry.id)
            }
        }
    }

    func getTargets(
        in spaceID: SpaceID, for client: BrowserExtensionServiceClientID
    ) throws -> Set<BrowserExtensionDebuggerTarget> {
        guard registrations[client]?.spaceID == spaceID, authorizeClient(client) else {
            throw BrowserExtensionDebuggerError.accessDenied
        }
        return Set(entries.values.map(\.target).filter { $0.spaceID == spaceID })
    }

    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionDebuggerEvent> {
        guard registrations[client] != nil else { return AsyncStream { $0.finish() } }
        return eventHub.events(for: client)
    }

    func reconcileTargets() {
        for entry in Array(entries.values) { _ = try? validate(entry) }
    }

    func cancel(target: BrowserExtensionDebuggerTarget) {
        if let entry = entries[target] { close(entry, reason: .canceledByUser) }
    }

    func shutdown() {
        for client in Array(registrations.keys) { unregister(client: client) }
    }

    private func authorize(_ client: BrowserExtensionServiceClientID, target: BrowserExtensionDebuggerTarget) throws {
        guard registrations[client]?.spaceID == target.spaceID, authorizeClient(client) else {
            throw BrowserExtensionDebuggerError.accessDenied
        }
    }

    private func validate(_ entry: Entry) throws {
        guard entries[entry.target] === entry else { throw BrowserExtensionDebuggerError.detachedWhileHandling }
        do { try authorize(entry.client, target: entry.target) } catch {
            close(entry, reason: .canceledByUser)
            throw error
        }
        switch resolveTarget(entry.target) {
        case .restricted:
            close(entry, reason: .canceledByUser)
            throw BrowserExtensionDebuggerError.accessDenied
        case .available(let page) where page === entry.page:
            if entry.phase == .attached && !entry.connection.isConnected {
                close(entry, reason: .targetClosed)
                throw BrowserExtensionDebuggerError.detachedWhileHandling
            }
        default:
            close(entry, reason: .targetClosed)
            throw BrowserExtensionDebuggerError.detachedWhileHandling
        }
    }

    private static func execute(_ command: BrowserExtensionDebuggerCommand, in entry: Entry) async throws -> Data {
        try Task.checkCancellation()
        guard let parameters = try JSONSerialization.jsonObject(with: command.parameters) as? [String: Any] else {
            throw BrowserExtensionDebuggerError.invalidRequest
        }
        let response: [String: Any]
        do {
            if command.method.hasPrefix("Runtime.") {
                response = try await entry.runtime.execute(command.method, parameters: parameters)
                // Chrome publishes console output and uncaught exceptions on the
                // Runtime domain, so a client that only enables Runtime still
                // expects them.
                if command.method == "Runtime.enable" { try await entry.console.enable() }
                if command.method == "Runtime.disable" { entry.console.disable() }
            } else if command.method == "Page.captureScreenshot" {
                response = try await entry.screenshot.capture(parameters: parameters)
            } else if command.method.hasPrefix("Page.") {
                response = try await entry.pageDomain.execute(command.method, parameters: parameters)
            } else if command.method.hasPrefix("Network.") {
                response = try await entry.network.execute(command.method, parameters: parameters)
            } else if command.method.hasPrefix("Input.") {
                response = try await entry.input.execute(command.method, parameters: parameters)
            } else if command.method.hasPrefix("Target.") || command.method.hasPrefix("Emulation.") {
                response = try await entry.targetDomain.execute(command.method, parameters: parameters)
            } else {
                throw BrowserChromeDebuggerProtocolError.unsupportedCommand(command.method)
            }
        } catch let error as BrowserChromeDebuggerProtocolError {
            // An unimplemented method leaves as a Domain value so callers above
            // the platform layer can restate it in the protocol's own words.
            if case .unsupportedCommand(let method) = error {
                entry.unsupported.record(method, client: entry.client)
                throw BrowserExtensionDebuggerError.unsupportedCommand(method)
            }
            throw error
        }
        return try JSONSerialization.data(withJSONObject: response)
    }

    private func complete(_ result: Result<Data, Error>, requestID: UUID, entry: Entry) {
        guard (try? validate(entry)) != nil,
            let pending = entry.pending.removeValue(forKey: requestID)
        else { return }
        pending.continuation.resume(with: result)
    }

    private func cancelCommand(_ requestID: UUID, target: BrowserExtensionDebuggerTarget, entryID: UUID) {
        guard let entry = entries[target], entry.id == entryID,
            let pending = entry.pending.removeValue(forKey: requestID)
        else { return }
        pending.task.cancel()
        pending.continuation.resume(throwing: CancellationError())
    }

    private func closeIfCurrent(target: BrowserExtensionDebuggerTarget, id: UUID) {
        if let entry = entries[target], entry.id == id { close(entry) }
    }

    private func close(_ entry: Entry, reason: BrowserExtensionDebuggerEvent.DetachReason? = nil) {
        guard entries[entry.target] === entry else { return }
        entries[entry.target] = nil
        let pending = entry.pending
        entry.pending.removeAll()
        for request in pending.values {
            request.task.cancel()
            request.continuation.resume(throwing: BrowserExtensionDebuggerError.detachedWhileHandling)
        }
        entry.connection.onEvent = nil
        entry.stopPublishing()
        entry.connection.disconnect()
        refreshSessions()
        if let reason {
            eventHub.publish(.init(target: entry.target, kind: .detached(reason)), to: entry.client)
        }
    }

    private func refreshSessions() {
        sessions = entries.values.compactMap { entry in
            guard let registration = registrations[entry.client] else { return nil }
            return .init(
                id: entry.id, target: entry.target, clientID: entry.client,
                displayName: registration.displayName, phase: entry.phase)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
