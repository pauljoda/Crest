import Foundation
import WebKit
import os

extension BrowserExtensionTabWindowCoordinator {
    private static let debuggerLog = Logger(
        subsystem: ProductIdentity.serviceNamespace,
        category: "extension-diagnostics"
    )

    /// The extension that verified itself into this debugger client, if any.
    func debuggerIdentity(for client: BrowserExtensionServiceClientID) -> BrowserExtensionDebuggerIdentity? {
        debuggerIdentitiesByClient[client]
    }

    /// The extension currently holding — or currently negotiating — a session
    /// on `target`.
    ///
    /// A target carries at most one binding, so this is what lets the session
    /// store's resolver re-check host access for the right package on every
    /// command without the port having to carry a client through.
    func debuggerIdentity(forTarget target: BrowserExtensionDebuggerTarget) -> BrowserExtensionDebuggerIdentity? {
        debuggerBindings.values.first { $0.target == target }?.identity
    }

    func registerDebuggerClient(_ identity: BrowserExtensionDebuggerIdentity, for context: WKWebExtensionContext) {
        let client = BrowserExtensionServiceClientID.scoped(
            extensionID: identity.extensionID, spaceID: identity.spaceID)
        debuggerClientsByContext[ObjectIdentifier(context)] = client
        debuggerIdentitiesByClient[client] = identity
        debuggerService?.register(client: client, spaceID: identity.spaceID, displayName: identity.displayName)
    }

    func unregisterDebuggerClient(for context: WKWebExtensionContext) {
        guard let client = debuggerClientsByContext.removeValue(forKey: ObjectIdentifier(context)) else { return }
        debuggerIdentitiesByClient[client] = nil
        debuggerBindings = debuggerBindings.filter { $0.value.client != client }
        debuggerService?.unregister(client: client)
    }

    /// Publishes a store event to the JavaScript watch that owns its session.
    ///
    /// The envelope carries the session token rather than a tab index: the
    /// receiving runtime already knows which tab the token belongs to, and a
    /// detached session's token stops resolving on both sides at once.
    func debuggerEventMessage(_ event: BrowserExtensionDebuggerEvent) -> [String: Any]? {
        guard let entry = debuggerBindings.first(where: { $0.value.target == event.target }) else { return nil }
        var message: [String: Any] = ["api": "debugger.event", "sessionToken": entry.key]
        switch event.kind {
        case .protocolMessage(let method, let parameters):
            message["kind"] = "event"
            message["method"] = method
            if let params = try? JSONSerialization.jsonObject(with: parameters) as? [String: Any] {
                message["params"] = params
            }
        case .detached(let reason):
            message["kind"] = "detach"
            message["reason"] = reason.rawValue
            debuggerBindings[entry.key] = nil
        }
        return message
    }

    func handleCapabilityBrokerDebugger(
        _ message: Any, applicationIdentifier: String?, controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard applicationIdentifier == BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
            let payload = message as? [String: Any], let api = payload["api"] as? String,
            BrowserExtensionDebuggerBrokerRequest.Operation(rawValue: api) != nil
        else { return false }
        do {
            let request = try BrowserExtensionDebuggerBrokerRequest(message: payload)
            guard let authorization = verifiedNativeMessagingAuthorizations[ObjectIdentifier(extensionContext)] else {
                throw BrowserExtensionNativeMessagingError.unverifiedExtension
            }
            guard authorization.allowsInternalCapabilityBroker, authorization.grants("debugger") else {
                throw BrowserExtensionCapabilityBrokerError.permissionDenied("debugger")
            }
            guard let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: extensionContext),
                let client = debuggerClientsByContext[ObjectIdentifier(extensionContext)],
                let identity = debuggerIdentitiesByClient[client], identity.spaceID == spaceID,
                let service = debuggerService
            else {
                throw BrowserExtensionDebuggerBrokerError.restricted
            }
            switch request.operation {
            case .attach:
                attachDebugger(request, client: client, identity: identity, service: service, reply: replyHandler)
            case .detach:
                try detachDebugger(request, client: client, service: service)
                replyHandler(["ok": true], nil)
            case .sendCommand:
                sendDebuggerCommand(request, client: client, service: service, reply: replyHandler)
            case .getTargets:
                replyHandler(["targets": debuggerTargets(in: spaceID, client: client, service: service)], nil)
            }
        } catch {
            replyHandler(nil, error)
        }
        return true
    }

    /// Binds the tab once, then asks for the user's consent before the session
    /// store ever sees the request.
    private func attachDebugger(
        _ request: BrowserExtensionDebuggerBrokerRequest, client: BrowserExtensionServiceClientID,
        identity: BrowserExtensionDebuggerIdentity, service: any BrowserExtensionDebuggerHandling,
        reply: @escaping (Any?, (any Error)?) -> Void
    ) {
        let target: BrowserExtensionDebuggerTarget
        do {
            // Chrome's order, which packages observe: resolve the debuggee,
            // then the protocol version, then existing attachments.
            target = try debuggerTarget(request, in: identity.spaceID)
            guard
                BrowserExtensionDebuggerTargetPolicy.supportedProtocolVersions
                    .contains(request.requiredVersion)
            else {
                throw BrowserExtensionDebuggerBrokerError.unsupportedVersion(request.requiredVersion)
            }
            guard !debuggerBindings.values.contains(where: { $0.target == target }) else {
                throw BrowserExtensionDebuggerBrokerError.alreadyAttached(request.tabID)
            }
        } catch {
            reply(nil, error)
            return
        }
        let token = UUID().uuidString
        debuggerBindings[token] = .init(target: target, client: client, identity: identity, tabID: request.tabID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let consented = await self.debuggerConsent?(identity) ?? false
            guard consented else {
                self.debuggerBindings[token] = nil
                reply(nil, BrowserExtensionDebuggerBrokerError.restricted)
                return
            }
            do {
                try await service.attach(to: target, for: client, requiredVersion: request.requiredVersion)
                reply(["sessionToken": token], nil)
            } catch {
                self.debuggerBindings[token] = nil
                reply(nil, Self.debuggerBrokerError(error, tabID: request.tabID))
            }
        }
    }

    private func detachDebugger(
        _ request: BrowserExtensionDebuggerBrokerRequest, client: BrowserExtensionServiceClientID,
        service: any BrowserExtensionDebuggerHandling
    ) throws {
        guard let token = request.sessionToken, let binding = debuggerBindings[token], binding.client == client else {
            throw BrowserExtensionDebuggerBrokerError.notAttached(request.tabID)
        }
        debuggerBindings[token] = nil
        do { try service.detach(from: binding.target, for: client) } catch {
            throw Self.debuggerBrokerError(error, tabID: binding.tabID)
        }
    }

    private func sendDebuggerCommand(
        _ request: BrowserExtensionDebuggerBrokerRequest, client: BrowserExtensionServiceClientID,
        service: any BrowserExtensionDebuggerHandling, reply: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard let token = request.sessionToken, let binding = debuggerBindings[token], binding.client == client,
            let method = request.method
        else {
            reply(nil, BrowserExtensionDebuggerBrokerError.notAttached(request.tabID))
            return
        }
        Task { @MainActor [weak self] in
            do {
                let data = try await service.sendCommand(
                    .init(method: method, parameters: request.parameters), to: binding.target, for: client)
                let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                reply(["result": result], nil)
            } catch {
                switch error as? BrowserExtensionDebuggerError {
                case .unsupportedCommand:
                    // Demand for the domains Crest has not built is only
                    // measurable if every refusal is recorded.
                    Self.debuggerLog.notice(
                        """
                        Extension \(binding.identity.extensionID, privacy: .public) requested unimplemented \
                        debugger command \(method, privacy: .public).
                        """
                    )
                case .detachedWhileHandling:
                    self?.debuggerBindings[token] = nil
                default:
                    break
                }
                reply(nil, Self.debuggerBrokerError(error, tabID: binding.tabID))
            }
        }
    }

    /// Every live tab in the Space, flagged with whether a debugger holds it.
    ///
    /// Transient pages are excluded for the same reason the sidebar excludes
    /// them: they are not addressable tabs, so naming one would hand back a
    /// target that can never be attached.
    private func debuggerTargets(
        in spaceID: SpaceID, client: BrowserExtensionServiceClientID, service: any BrowserExtensionDebuggerHandling
    ) -> [[String: Any]] {
        guard let state = currentState?.space(spaceID) else { return [] }
        let attached = (try? service.getTargets(in: spaceID, for: client)) ?? []
        let transient = Set((transientTabsBySpace[spaceID] ?? []).map(\.id))
        return state.tabs.filter { !transient.contains($0.id) }.map { tab in
            var info: [String: Any] = [
                "id": "crest-tab-\(tab.id.rawValue.uuidString.lowercased())",
                "tabIndex": tab.index,
                "title": tab.title,
                "attached": attached.contains(.init(spaceID: spaceID, tabID: tab.id)),
            ]
            if let url = tab.url?.absoluteString { info["url"] = url }
            return info
        }
    }

    /// Resolves the caller's tab index and URL against live session state.
    ///
    /// This runs once per attachment. The index is a claim about the primary
    /// window's ordering that Crest re-checks here; after this point the
    /// session is addressed by the token bound to the resulting `TabID`.
    private func debuggerTarget(
        _ request: BrowserExtensionDebuggerBrokerRequest, in spaceID: SpaceID
    ) throws -> BrowserExtensionDebuggerTarget {
        guard let state = currentState?.space(spaceID), let index = request.tabIndex,
            let tab = state.tabs.first(where: { $0.index == index }),
            !(transientTabsBySpace[spaceID] ?? []).contains(where: { $0.id == tab.id })
        else {
            throw BrowserExtensionDebuggerBrokerError.noTarget(request.tabID)
        }
        guard BrowserExtensionTabIdentity.urlMatches(reported: request.url, state: tab.url) else {
            throw BrowserExtensionDebuggerBrokerError.noTarget(request.tabID)
        }
        return .init(spaceID: spaceID, tabID: tab.id)
    }

    /// Restates a session-store or protocol failure in Chrome's own words.
    private static func debuggerBrokerError(_ error: any Error, tabID: Int) -> any Error {
        switch error as? BrowserExtensionDebuggerError {
        case .alreadyAttached: BrowserExtensionDebuggerBrokerError.alreadyAttached(tabID)
        case .notAttached: BrowserExtensionDebuggerBrokerError.notAttached(tabID)
        case .accessDenied: BrowserExtensionDebuggerBrokerError.restricted
        case .detachedWhileHandling: BrowserExtensionDebuggerBrokerError.detachedWhileHandling
        case .unsupportedVersion(let version): BrowserExtensionDebuggerBrokerError.unsupportedVersion(version)
        case .invalidRequest: BrowserExtensionDebuggerBrokerError.invalidRequest
        case .unsupportedCommand(let method): BrowserExtensionDebuggerBrokerError.unsupportedCommand(method)
        case nil: error
        }
    }
}
