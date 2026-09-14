import Foundation

/// Keeps folder edits in their owning workspace while one Space's extension
/// context can see tabs in both shared and temporary windows.
@MainActor
final class BrowserExtensionTabGroupRoutingService: BrowserExtensionTabGroupHandling {
    struct Source {
        let service: any BrowserExtensionTabGroupHandling
        let session: BrowserSession?
    }

    private struct SubscriptionKey: Hashable {
        let service: ObjectIdentifier
        let client: BrowserExtensionServiceClientID
    }

    private let sources: () -> [Source]
    private var clients: [BrowserExtensionServiceClientID: SpaceID] = [:]
    private var subscriptions: [SubscriptionKey: [Task<Void, Never>]] = [:]
    private var knownSources: [ObjectIdentifier: any BrowserExtensionTabGroupHandling] = [:]
    private let hub = BrowserExtensionTabGroupEventHub()

    init(sources: @escaping () -> [Source]) { self.sources = sources }

    deinit {
        for tasks in subscriptions.values { for task in tasks { task.cancel() } }
    }

    var revision: Int { sources().reduce(0) { $0 &+ $1.service.revision } }

    func register(client: BrowserExtensionServiceClientID, spaceID: SpaceID) {
        clients[client] = spaceID
        refreshSources()
    }

    func unregister(client: BrowserExtensionServiceClientID) {
        clients[client] = nil
        for source in sources() { source.service.unregister(client: client) }
        for key in Array(subscriptions.keys) where key.client == client {
            for task in subscriptions.removeValue(forKey: key) ?? [] { task.cancel() }
        }
        hub.remove(client: client)
    }

    func space(for client: BrowserExtensionServiceClientID) -> SpaceID? { clients[client] }

    func refreshSources() {
        let current = sources()
        let identities = Set(current.map { ObjectIdentifier($0.service) })
        for (identity, service) in knownSources where !identities.contains(identity) {
            for (client, spaceID) in clients {
                for group in service.groups(in: spaceID) {
                    hub.publish(.init(kind: .removed, group: group), to: [client])
                }
                service.unregister(client: client)
            }
        }
        knownSources = Dictionary(uniqueKeysWithValues: current.map { (ObjectIdentifier($0.service), $0.service) })
        for key in Array(subscriptions.keys) where !identities.contains(key.service) {
            for task in subscriptions.removeValue(forKey: key) ?? [] { task.cancel() }
        }
        for source in current {
            for (client, spaceID) in clients {
                let key = SubscriptionKey(service: ObjectIdentifier(source.service), client: client)
                guard subscriptions[key] == nil else { continue }
                source.service.register(client: client, spaceID: spaceID)
                let events = source.service.events(for: client)
                let memberships = source.service.membershipEvents(for: client)
                subscriptions[key] = [
                    Task { @MainActor [weak self] in
                        for await event in events {
                            guard !Task.isCancelled else { return }
                            self?.hub.publish(event, to: [client])
                        }
                    },
                    Task { @MainActor [weak self] in
                        for await membership in memberships {
                            guard !Task.isCancelled else { return }
                            self?.hub.publishMembership(membership, to: [client])
                        }
                    },
                ]
            }
        }
    }

    func groups(in spaceID: SpaceID) -> [BrowserExtensionTabGroup] {
        sources().flatMap { $0.service.groups(in: spaceID) }
    }

    func group(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID) throws -> BrowserExtensionTabGroup {
        try service(for: id, in: spaceID).group(id, in: spaceID)
    }

    func membership(in spaceID: SpaceID) -> [TabID: BrowserExtensionTabGroupID] {
        sources().reduce(into: [:]) { result, source in
            result.merge(source.service.membership(in: spaceID)) { existing, _ in existing }
        }
    }

    func group(_ tabs: [TabID], in spaceID: SpaceID, into existingID: BrowserExtensionTabGroupID?) throws
        -> BrowserExtensionTabGroup
    {
        let service = try service(for: tabs, in: spaceID)
        if let existingID, try self.service(for: existingID, in: spaceID) !== service {
            throw BrowserExtensionTabGroupError.unknownGroup(existingID)
        }
        return try service.group(tabs, in: spaceID, into: existingID)
    }

    func update(
        _ id: BrowserExtensionTabGroupID, in spaceID: SpaceID,
        title: String?, color: BrowserExtensionTabGroupColor?, isCollapsed: Bool?
    ) throws -> BrowserExtensionTabGroup {
        try service(for: id, in: spaceID).update(id, in: spaceID, title: title, color: color, isCollapsed: isCollapsed)
    }

    func ungroup(_ tabs: [TabID], in spaceID: SpaceID) {
        guard let service = try? service(for: tabs, in: spaceID) else { return }
        service.ungroup(tabs, in: spaceID)
    }

    func move(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID, to index: Int) throws -> BrowserExtensionTabGroup {
        try service(for: id, in: spaceID).move(id, in: spaceID, to: index)
    }

    func repair(using session: BrowserSession) {
        for source in sources() { source.service.repair(using: source.session ?? session) }
        refreshSources()
    }

    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionTabGroupEvent> {
        hub.events(for: client)
    }

    func membershipEvents(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionTabGroupEvent.Membership>
    {
        hub.membershipEvents(for: client)
    }

    private func service(for id: BrowserExtensionTabGroupID, in spaceID: SpaceID)
        throws -> any BrowserExtensionTabGroupHandling
    {
        guard let source = sources().first(where: { (try? $0.service.group(id, in: spaceID)) != nil }) else {
            throw BrowserExtensionTabGroupError.unknownGroup(id)
        }
        return source.service
    }

    private func service(for tabs: [TabID], in spaceID: SpaceID) throws -> any BrowserExtensionTabGroupHandling {
        let current = sources()
        if current.count == 1, let service = current.first?.service { return service }
        guard !tabs.isEmpty,
            let source = current.first(where: { source in
                let available = Set(source.session?.space(id: spaceID)?.tabs.map(\.id) ?? [])
                return tabs.allSatisfy(available.contains)
            })
        else {
            if let first = tabs.first { throw BrowserExtensionTabGroupError.unavailableTab(first) }
            throw BrowserExtensionTabGroupError.emptyTabList
        }
        return source.service
    }
}
