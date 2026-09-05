import Foundation
import Observation

/// Projects Crest folders into extension API values. Folder metadata, hierarchy,
/// membership and ordering live exclusively in BrowserSession.
@Observable
@MainActor
final class BrowserExtensionTabGroupStore: BrowserExtensionTabGroupHandling {
    private(set) var revision = 0
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var idsBySpace: [SpaceID: [FolderID: BrowserExtensionTabGroupID]] = [:]
    /// Last announced projection, used only to derive API events.
    @ObservationIgnored private var positions: [BrowserExtensionTabGroupID: Int] = [:]
    @ObservationIgnored private var announced: [BrowserExtensionTabGroup] = []
    @ObservationIgnored private var announcedTabOrder: [SpaceID: [TabID]] = [:]
    @ObservationIgnored private var spacesByClient: [BrowserExtensionServiceClientID: SpaceID] = [:]
    @ObservationIgnored private let eventHub = BrowserExtensionTabGroupEventHub()
    @ObservationIgnored var sessionSnapshot: (() -> BrowserSession?)?
    @ObservationIgnored var commitSession: ((BrowserSession) -> Void)?

    func register(client: BrowserExtensionServiceClientID, spaceID: SpaceID) { spacesByClient[client] = spaceID }
    func unregister(client: BrowserExtensionServiceClientID) {
        guard spacesByClient.removeValue(forKey: client) != nil else { return }
        eventHub.remove(client: client)
    }
    func space(for client: BrowserExtensionServiceClientID) -> SpaceID? { spacesByClient[client] }

    func groups(in spaceID: SpaceID) -> [BrowserExtensionTabGroup] {
        _ = revision
        if let session = sessionSnapshot?() { repair(using: session) }
        return announced.filter { $0.spaceID == spaceID }
    }

    func group(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID) throws -> BrowserExtensionTabGroup {
        guard let group = groups(in: spaceID).first(where: { $0.id == id }) else {
            throw BrowserExtensionTabGroupError.unknownGroup(id)
        }
        return group
    }

    func membership(in spaceID: SpaceID) -> [TabID: BrowserExtensionTabGroupID] {
        Dictionary(uniqueKeysWithValues: groups(in: spaceID).flatMap { group in group.tabs.map { ($0, group.id) } })
    }

    @discardableResult
    func group(_ tabs: [TabID], in spaceID: SpaceID, into existingID: BrowserExtensionTabGroupID?) throws
        -> BrowserExtensionTabGroup
    {
        guard !tabs.isEmpty else { throw BrowserExtensionTabGroupError.emptyTabList }
        guard var next = sessionSnapshot?(), commitSession != nil else {
            throw BrowserExtensionTabGroupError.unavailableTab(tabs[0])
        }
        let space = next.space(id: spaceID)
        let available = Set(space?.tabs.filter { $0.placement != .pinned }.map(\.id) ?? [])
        if let invalid = tabs.first(where: { !available.contains($0) }) {
            throw BrowserExtensionTabGroupError.unavailableTab(invalid)
        }
        let folderID: FolderID
        if let existingID {
            folderID = try group(existingID, in: spaceID).folderID
            guard let location = space?.folders.first(where: { $0.id == folderID })?.location else {
                throw BrowserExtensionTabGroupError.unknownGroup(existingID)
            }
            _ = next.fileTabs(tabs, in: spaceID, into: folderID, location: location)
        } else {
            let location: BrowserFolderLocation =
                space?.tabs.first(where: { $0.id == tabs[0] })?.placement == .saved ? .saved : .current
            guard
                let created = next.createTabFolder(
                    tabs, in: spaceID, location: location, title: "",
                    color: BrowserExtensionTabGroupColor.grey.brandColor)
            else {
                throw BrowserExtensionTabGroupError.unavailableTab(tabs[0])
            }
            folderID = created
        }
        commit(next)
        guard let value = groups(in: spaceID).first(where: { $0.folderID == folderID }) else {
            throw BrowserExtensionTabGroupError.unavailableTab(tabs[0])
        }
        return value
    }

    @discardableResult
    func update(
        _ id: BrowserExtensionTabGroupID, in spaceID: SpaceID, title: String?,
        color: BrowserExtensionTabGroupColor?, isCollapsed: Bool?
    ) throws -> BrowserExtensionTabGroup {
        let current = try group(id, in: spaceID)
        guard var next = sessionSnapshot?(),
            let si = next.spaces.firstIndex(where: { $0.id == spaceID }),
            let fi = next.spaces[si].folders.firstIndex(where: { $0.id == current.folderID })
        else { throw BrowserExtensionTabGroupError.unknownGroup(id) }
        if let title { next.spaces[si].folders[fi].title = title }
        if let color { next.spaces[si].folders[fi].color = color.brandColor }
        if let isCollapsed { _ = next.setFolderCollapsed(current.folderID, in: spaceID, isCollapsed: isCollapsed) }
        commit(next)
        return try group(id, in: spaceID)
    }

    func ungroup(_ tabs: [TabID], in spaceID: SpaceID) {
        guard var next = sessionSnapshot?(), let space = next.space(id: spaceID) else { return }
        let requested = Set(tabs)
        let grouped = membership(in: spaceID)
        for location in [BrowserFolderLocation.saved, .current] {
            let moving = space.tabs.filter {
                requested.contains($0.id) && grouped[$0.id] != nil && $0.placement == location.tabPlacement
            }.map(\.id)
            _ = next.fileTabs(moving, in: spaceID, into: nil, location: location)
        }
        commit(next)
    }

    func move(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID, to index: Int) throws -> BrowserExtensionTabGroup {
        let group = try group(id, in: spaceID)
        guard index >= -1, var next = sessionSnapshot?(), let space = next.space(id: spaceID),
            let folder = space.folders.first(where: { $0.id == group.folderID })
        else { throw BrowserExtensionTabGroupBrokerError.failedToMove }
        let subtree = space.folderTree.descendants(of: folder.id).union([folder.id])
        let remaining = space.tabs.filter { $0.folderID.map(subtree.contains) != true }
        let anchor = index == -1 || index >= remaining.count ? nil : remaining[index]
        if anchor?.placement == .pinned {
            throw BrowserExtensionTabGroupBrokerError.failedToMove
        }
        // A Chrome index cannot split another folder's contiguous run.
        if index > 0, index < remaining.count, let folderID = remaining[index].folderID,
            remaining[index - 1].folderID == folderID
        {
            throw BrowserExtensionTabGroupBrokerError.failedToMove
        }
        let placement = anchor?.placement ?? remaining.last?.placement ?? folder.location.tabPlacement
        let location: BrowserFolderLocation = placement == .saved ? .saved : .current
        let parentID = location == folder.location ? folder.parentID : nil
        let sibling = anchor?.folderID.flatMap { id in space.folders.first { $0.id == id } }
        // A flat Chrome index cannot insert a group into the middle of a
        // different folder hierarchy. Preserve the existing tree boundary.
        if let sibling, sibling.parentID != parentID {
            throw BrowserExtensionTabGroupBrokerError.failedToMove
        }
        _ = next.moveFolder(
            folder.id, in: spaceID, into: parentID, before: sibling?.id,
            location: location, beforeTabID: anchor?.id)
        commit(next)
        return try self.group(id, in: spaceID)
    }

    func repair(using session: BrowserSession) {
        let nextTabOrder = Dictionary(uniqueKeysWithValues: session.spaces.map { ($0.id, $0.tabs.map(\.id)) })
        let previousTabOrder = announcedTabOrder
        announcedTabOrder = nextTabOrder
        var projected: [BrowserExtensionTabGroup] = []
        var nextPositions: [BrowserExtensionTabGroupID: Int] = [:]
        for space in session.spaces {
            let sections = space.tabSections
            let tabPositions = Dictionary(
                uniqueKeysWithValues: space.tabs.enumerated().map { ($0.element.id, $0.offset) })
            var live: Set<FolderID> = []
            for folder in space.folders {
                let tabs = sections.tabs(in: folder.id).filter { $0.placement == folder.location.tabPlacement }.map(
                    \.id)
                guard !tabs.isEmpty else { continue }
                live.insert(folder.id)
                let id: BrowserExtensionTabGroupID
                if let existing = idsBySpace[space.id]?[folder.id] {
                    id = existing
                } else {
                    id = .init(rawValue: nextID)
                    nextID += 1
                    idsBySpace[space.id, default: [:]][folder.id] = id
                }
                nextPositions[id] = tabs.first.flatMap { tabPositions[$0] }
                projected.append(
                    .init(
                        id: id, folderID: folder.id, spaceID: space.id, tabs: tabs,
                        title: folder.title, color: .nearest(to: folder.color), isCollapsed: folder.isCollapsed))
            }
            idsBySpace[space.id] = idsBySpace[space.id]?.filter { live.contains($0.key) }
        }
        let liveSpaces = Set(session.spaces.map(\.id))
        idsBySpace = idsBySpace.filter { liveSpaces.contains($0.key) }
        for (client, spaceID) in spacesByClient where !liveSpaces.contains(spaceID) { unregister(client: client) }
        guard projected != announced || nextPositions != positions || nextTabOrder != previousTabOrder else { return }
        let previousPositions = positions
        positions = nextPositions
        let previous = announced
        announced = projected
        revision &+= 1
        let previousMembership = Dictionary(
            uniqueKeysWithValues: previous.flatMap { group in
                group.tabs.map { ($0, group.id) }
            })
        let currentMembership = Dictionary(
            uniqueKeysWithValues: projected.flatMap { group in
                group.tabs.map { ($0, group.id) }
            })
        for space in session.spaces {
            let previousTabs = Set(previousTabOrder[space.id] ?? [])
            let changes = space.tabs.compactMap { tab -> BrowserExtensionTabGroupEvent.Membership.Change? in
                // Creation/removal have their own native events. Only tabs
                // present in both snapshots can change membership here.
                guard previousTabs.contains(tab.id), previousMembership[tab.id] != currentMembership[tab.id]
                else { return nil }
                return .init(tabID: tab.id, groupID: currentMembership[tab.id])
            }
            if !changes.isEmpty {
                eventHub.publishMembership(
                    .init(spaceID: space.id, changes: changes),
                    to: spacesByClient.filter { $0.value == space.id }.keys)
            }
        }
        let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let current = Dictionary(uniqueKeysWithValues: projected.map { ($0.id, $0) })
        for group in previous where current[group.id] == nil { publish(.removed, group) }
        for group in projected {
            guard let prior = old[group.id] else {
                publish(.created, group)
                continue
            }
            if prior.title != group.title || prior.color != group.color || prior.isCollapsed != group.isCollapsed {
                publish(.updated, group)
            }
            if prior.tabs == group.tabs, previousPositions[group.id] != nextPositions[group.id] {
                publish(.moved, group)
            }
        }
        for (client, spaceID) in spacesByClient where !liveSpaces.contains(spaceID) { unregister(client: client) }
    }

    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionTabGroupEvent> {
        eventHub.events(for: client)
    }

    func membershipEvents(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionTabGroupEvent.Membership>
    {
        eventHub.membershipEvents(for: client)
    }

    private func commit(_ session: BrowserSession) {
        guard session != sessionSnapshot?() else { return }
        commitSession?(session)
        repair(using: session)
    }

    private func publish(_ kind: BrowserExtensionTabGroupEvent.Kind, _ group: BrowserExtensionTabGroup) {
        eventHub.publish(.init(kind: kind, group: group), to: spacesByClient.filter { $0.value == group.spaceID }.keys)
    }
}
