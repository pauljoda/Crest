import Foundation

extension BrowserSession {
    mutating func cleanupCurrentTabs(olderThan lifetime: TimeInterval, now: Date = .now) {
        for index in spaces.indices {
            cleanupCurrentTabs(inSpaceAt: index, olderThan: lifetime, now: now)
        }
    }

    mutating func cleanupCurrentTabsUsingSpacePreferences(now: Date = .now) {
        for index in spaces.indices {
            guard let lifetime = spaces[index].browsingPreferences
                .currentTabCleanupPolicy.lifetime else { continue }
            cleanupCurrentTabs(inSpaceAt: index, olderThan: lifetime, now: now)
        }
    }

    mutating func cleanupCurrentTabs(in spaceID: SpaceID, now: Date = .now) {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }),
              let lifetime = spaces[index].browsingPreferences
                .currentTabCleanupPolicy.lifetime else { return }
        cleanupCurrentTabs(inSpaceAt: index, olderThan: lifetime, now: now)
    }

    mutating func restoreArchivedTab(_ tabID: TabID, at date: Date = .now) {
        guard let spaceIndex = selectedSpaceIndex else { return }
        guard let archiveIndex = spaces[spaceIndex].archivedTabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }
        var tab = spaces[spaceIndex].archivedTabs.remove(at: archiveIndex).tab
        tab.placement = .current
        tab.folderID = nil
        tab.splitGroupID = nil
        tab.lastActivatedAt = date
        tab.markPositionModified(at: date)
        let insertionIndex = spaces[spaceIndex].tabs.firstIndex { $0.placement == .current }
            ?? spaces[spaceIndex].tabs.endIndex
        spaces[spaceIndex].tabs.insert(tab, at: insertionIndex)
        spaces[spaceIndex].selectedTabID = tab.id
    }

    private mutating func cleanupCurrentTabs(
        inSpaceAt index: Int,
        olderThan lifetime: TimeInterval,
        now: Date
    ) {
        let selectedID = spaces[index].selectedTabID
        let expiredTabs = spaces[index].tabs.filter { tab in
            tab.placement == .current
                && !tab.isStartPage
                && tab.id != selectedID
                && now.timeIntervalSince(tab.lastActivatedAt) > lifetime
        }
        spaces[index].archivedTabs.append(contentsOf: expiredTabs.map { source in
            var tab = source
            tab.faviconData = nil
            // An archived tab leaves its split. The survivor rule is not applied
            // here: automatic cleanup is not a user mutation, and a partially
            // merged group must not be dissolved behind the person's back.
            tab.splitGroupID = nil
            return ArchivedTab(tab: tab, archivedAt: now, reason: .autoCleanup)
        })
        let expiredIDs = Set(expiredTabs.map(\.id))
        spaces[index].tabs.removeAll { expiredIDs.contains($0.id) }
        ensureSelection(in: spaces[index].id)
    }

}
