import Foundation

/// Browser-owned group membership. The coordinator must validate live tabs and
/// apply their native ordering before publishing a successful API response.
/// Nothing here grants an extension access to another Space or exposes an API.
struct BrowserExtensionTabGroupRegistry: Sendable {
    private var nextID = 1
    private var groupsByID: [BrowserExtensionTabGroupID: BrowserExtensionTabGroup] = [:]

    func groups(in spaceID: SpaceID) -> [BrowserExtensionTabGroup] {
        groupsByID.values.filter { $0.spaceID == spaceID }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func get(_ id: BrowserExtensionTabGroupID, in spaceID: SpaceID) throws -> BrowserExtensionTabGroup {
        guard let group = groupsByID[id], group.spaceID == spaceID else {
            throw BrowserExtensionTabGroupError.unknownGroup(id)
        }
        return group
    }

    func groupID(for tabID: TabID, in spaceID: SpaceID) -> BrowserExtensionTabGroupID? {
        groupsByID.values.first { $0.spaceID == spaceID && $0.tabs.contains(tabID) }?.id
    }

    mutating func group(
        _ tabs: [TabID], in spaceID: SpaceID, into existingID: BrowserExtensionTabGroupID? = nil
    ) throws -> BrowserExtensionTabGroup {
        guard !tabs.isEmpty else { throw BrowserExtensionTabGroupError.emptyTabList }
        // Validate before removing membership so a rejected request is atomic.
        var group: BrowserExtensionTabGroup
        if let existingID {
            group = try get(existingID, in: spaceID)
        } else {
            group = .init(id: .init(rawValue: nextID), spaceID: spaceID, tabs: [])
            nextID += 1
        }
        let movingTabs = Set(tabs)
        removeMembership(movingTabs, in: spaceID, except: group.id)
        var members = Set(group.tabs)
        group.tabs.append(contentsOf: tabs.filter { members.insert($0).inserted })
        groupsByID[group.id] = group
        return group
    }

    mutating func update(
        _ id: BrowserExtensionTabGroupID, in spaceID: SpaceID,
        title: String? = nil, color: BrowserExtensionTabGroupColor? = nil, isCollapsed: Bool? = nil
    ) throws -> BrowserExtensionTabGroup {
        var group = try get(id, in: spaceID)
        if let title { group.title = title }
        if let color { group.color = color }
        if let isCollapsed { group.isCollapsed = isCollapsed }
        groupsByID[id] = group
        return group
    }

    mutating func ungroup(_ tabs: [TabID], in spaceID: SpaceID) {
        removeMembership(Set(tabs), in: spaceID)
    }

    mutating func repair(in spaceID: SpaceID, liveTabs: Set<TabID>) {
        let staleTabs = Set(groups(in: spaceID).flatMap(\.tabs)).subtracting(liveTabs)
        removeMembership(staleTabs, in: spaceID)
    }

    private mutating func removeMembership(
        _ tabs: Set<TabID>, in spaceID: SpaceID, except retainedID: BrowserExtensionTabGroupID? = nil
    ) {
        for var group in groups(in: spaceID) where group.id != retainedID {
            group.tabs.removeAll { tabs.contains($0) }
            groupsByID[group.id] = group.tabs.isEmpty ? nil : group
        }
    }
}
