import Foundation
import Observation

/// The live tab-group registry every extension in a Space shares.
///
/// Crest keeps group membership without drawing it. That is the one deviation
/// from Chrome worth stating plainly: `tabs.group` records a real, durable,
/// browser-owned grouping that `tabGroups.query` and `Tab.groupId` report
/// back truthfully, but the sidebar does not yet render a group and no tab is
/// reordered to sit beside its siblings. A registry that lied about ordering
/// would be worse than one that admits it has none — which is also why
/// `tabGroups.move` rejects rather than pretending to have moved anything.
///
/// Events are derived by diffing the registry around each mutation instead of
/// being announced by the caller. The registry drops a group when its last tab
/// leaves, and a caller that had to remember to announce that would eventually
/// forget.
@Observable
@MainActor
final class BrowserExtensionTabGroupStore: BrowserExtensionTabGroupHandling {
    /// Bumped on every accepted mutation so a future sidebar presentation can
    /// observe grouping without the store publishing its internals.
    private(set) var revision = 0

    @ObservationIgnored private var registry = BrowserExtensionTabGroupRegistry()
    @ObservationIgnored private var spacesByClient: [BrowserExtensionServiceClientID: SpaceID] = [:]
    @ObservationIgnored private var knownSpaces: Set<SpaceID> = []
    @ObservationIgnored private let eventHub = BrowserExtensionTabGroupEventHub()

    init() {}

    func register(client: BrowserExtensionServiceClientID, spaceID: SpaceID) {
        spacesByClient[client] = spaceID
    }

    func unregister(client: BrowserExtensionServiceClientID) {
        guard spacesByClient.removeValue(forKey: client) != nil else { return }
        eventHub.remove(client: client)
    }

    func space(for client: BrowserExtensionServiceClientID) -> SpaceID? {
        spacesByClient[client]
    }

    func groups(in spaceID: SpaceID) -> [BrowserExtensionTabGroup] {
        registry.groups(in: spaceID)
    }

    func group(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID) throws
        -> BrowserExtensionTabGroup
    {
        try registry.get(id, in: spaceID)
    }

    func membership(in spaceID: SpaceID) -> [TabID: BrowserExtensionTabGroupID] {
        var result: [TabID: BrowserExtensionTabGroupID] = [:]
        for group in registry.groups(in: spaceID) {
            for tab in group.tabs { result[tab] = group.id }
        }
        return result
    }

    @discardableResult
    func group(
        _ tabs: [TabID], in spaceID: SpaceID, into existingID: BrowserExtensionTabGroupID?
    ) throws -> BrowserExtensionTabGroup {
        let previous = registry.groups(in: spaceID)
        let group = try registry.group(tabs, in: spaceID, into: existingID)
        knownSpaces.insert(spaceID)
        publishChanges(from: previous, in: spaceID)
        return group
    }

    @discardableResult
    func update(
        _ id: BrowserExtensionTabGroupID, in spaceID: SpaceID,
        title: String?, color: BrowserExtensionTabGroupColor?, isCollapsed: Bool?
    ) throws -> BrowserExtensionTabGroup {
        let previous = registry.groups(in: spaceID)
        let group = try registry.update(
            id, in: spaceID, title: title, color: color, isCollapsed: isCollapsed)
        publishChanges(from: previous, in: spaceID)
        return group
    }

    func ungroup(_ tabs: [TabID], in spaceID: SpaceID) {
        let previous = registry.groups(in: spaceID)
        registry.ungroup(tabs, in: spaceID)
        publishChanges(from: previous, in: spaceID)
    }

    func repair(using session: BrowserSession) {
        let liveSpaces = Set(session.spaces.map(\.id))
        for spaceID in knownSpaces {
            let previous = registry.groups(in: spaceID)
            guard !previous.isEmpty else { continue }
            let liveTabs =
                session.space(id: spaceID).map { Set($0.tabs.map(\.id)) } ?? []
            registry.repair(in: spaceID, liveTabs: liveTabs)
            publishChanges(from: previous, in: spaceID)
        }
        knownSpaces.formIntersection(liveSpaces)
        for (client, spaceID) in spacesByClient where !liveSpaces.contains(spaceID) {
            unregister(client: client)
        }
    }

    func events(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionTabGroupEvent>
    {
        eventHub.events(for: client)
    }

    /// Diffs one Space and publishes what actually changed.
    ///
    /// `.updated` is reserved for the visual data Chrome fires it for. A tab
    /// joining or leaving a group changes `group.tabs` and nothing a Chrome
    /// extension would receive `tabGroups.onUpdated` for, so it is not
    /// published as one.
    private func publishChanges(
        from previous: [BrowserExtensionTabGroup], in spaceID: SpaceID
    ) {
        let current = registry.groups(in: spaceID)
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var events: [BrowserExtensionTabGroupEvent] = []
        for group in previous where currentByID[group.id] == nil {
            events.append(.init(kind: .removed, group: group))
        }
        for group in current {
            guard let existing = previousByID[group.id] else {
                events.append(.init(kind: .created, group: group))
                continue
            }
            guard !Self.visualsMatch(existing, group) else { continue }
            events.append(.init(kind: .updated, group: group))
        }
        guard !events.isEmpty || previous != current else { return }
        revision &+= 1
        guard !events.isEmpty else { return }
        let clients = spacesByClient.filter { $0.value == spaceID }.keys
        for event in events { eventHub.publish(event, to: clients) }
    }

    private static func visualsMatch(
        _ lhs: BrowserExtensionTabGroup, _ rhs: BrowserExtensionTabGroup
    ) -> Bool {
        lhs.title == rhs.title && lhs.color == rhs.color && lhs.isCollapsed == rhs.isCollapsed
    }
}
