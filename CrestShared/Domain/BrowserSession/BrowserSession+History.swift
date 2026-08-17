import Foundation

// MARK: - Recording

extension BrowserSession {
    static let maximumHistoryEntriesPerSpace = 5_000

    mutating func recordVisit(url: URL, title: String?, at date: Date = .now) {
        guard let normalizedURL = BrowserHistoryURL.normalized(url),
            let spaceIndex = selectedSpaceIndex
        else { return }
        recordVisit(
            normalizedURL: normalizedURL,
            title: title,
            inSpaceAt: spaceIndex,
            at: date
        )
    }

    mutating func recordVisit(
        url: URL,
        title: String?,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        guard let normalizedURL = BrowserHistoryURL.normalized(url),
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID })
        else { return }
        recordVisit(
            normalizedURL: normalizedURL,
            title: title,
            inSpaceAt: spaceIndex,
            at: date
        )
    }

    mutating func archiveTransientPage(
        url: URL,
        title: String?,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        let tab = BrowserTab(
            title: title.flatMap { $0.isEmpty ? nil : $0 }
                ?? url.host()
                ?? url.absoluteString,
            url: url,
            placement: .current,
            lastActivatedAt: date
        )
        spaces[spaceIndex].archivedTabs.append(
            ArchivedTab(tab: tab, archivedAt: date, reason: .quickWindow)
        )
    }

    private mutating func recordVisit(
        normalizedURL: URL,
        title: String?,
        inSpaceAt spaceIndex: Int,
        at date: Date
    ) {
        let resolvedTitle =
            title.flatMap { $0.isEmpty ? nil : $0 }
            ?? normalizedURL.host()
            ?? normalizedURL.absoluteString

        if let historyIndex = spaces[spaceIndex].history.firstIndex(where: { $0.url == normalizedURL }) {
            var entry = spaces[spaceIndex].history.remove(at: historyIndex)
            entry.title = resolvedTitle
            entry.lastVisitedAt = date
            entry.visitCount += 1
            spaces[spaceIndex].history.insert(entry, at: 0)
        } else {
            spaces[spaceIndex].history.insert(
                BrowserHistoryEntry(
                    url: normalizedURL,
                    title: resolvedTitle,
                    firstVisitedAt: date,
                    lastVisitedAt: date
                ),
                at: 0
            )
        }

        if spaces[spaceIndex].history.count > Self.maximumHistoryEntriesPerSpace {
            spaces[spaceIndex].history.removeLast(
                spaces[spaceIndex].history.count - Self.maximumHistoryEntriesPerSpace
            )
        }
    }

    @discardableResult
    mutating func clearHistory(in spaceID: SpaceID) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else {
            return false
        }
        spaces[spaceIndex].history.removeAll()
        return true
    }

    mutating func clearHistory() {
        clearHistory(in: selectedSpaceID)
    }

}

// MARK: - Deletion

/// Targeted history removal.
///
/// Browsing only ever appends, so until now a Space's history could be cleared
/// wholesale but never edited. `chrome.history.deleteUrl` and `deleteRange`
/// need finer removal, and so does any future "forget this site" affordance.
extension BrowserSession {
    /// Removes the entry for `url`, reporting whether one was present.
    ///
    /// The URL is normalized the same way ``recordVisit(url:title:at:)``
    /// normalizes it, so callers can pass the address they navigated to rather
    /// than the stored form.
    @discardableResult
    mutating func removeHistory(for url: URL, in spaceID: SpaceID) -> Bool {
        guard let normalizedURL = BrowserHistoryURL.normalized(url),
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID })
        else {
            return false
        }

        let originalCount = spaces[spaceIndex].history.count
        spaces[spaceIndex].history.removeAll { $0.url == normalizedURL }
        return spaces[spaceIndex].history.count != originalCount
    }

    /// Removes every entry last visited within `startDate ..< endDate`,
    /// reporting whether anything was removed.
    ///
    /// The window is half-open to match `chrome.history.deleteRange`, and an
    /// entry is judged only by its last visit: Crest keeps no per-visit rows,
    /// so an older visit to a page that was also opened after the window cannot
    /// be removed on its own.
    @discardableResult
    mutating func removeHistory(
        from startDate: Date,
        until endDate: Date,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID })
        else {
            return false
        }

        let originalCount = spaces[spaceIndex].history.count
        spaces[spaceIndex].history.removeAll { entry in
            entry.lastVisitedAt >= startDate && entry.lastVisitedAt < endDate
        }
        return spaces[spaceIndex].history.count != originalCount
    }
}

// MARK: - Cleanup

extension BrowserSession {
    mutating func cleanupCurrentTabs(olderThan lifetime: TimeInterval, now: Date = .now) {
        for index in spaces.indices {
            cleanupCurrentTabs(inSpaceAt: index, olderThan: lifetime, now: now)
        }
    }

    mutating func cleanupCurrentTabsUsingSpacePreferences(now: Date = .now) {
        for index in spaces.indices {
            guard
                let lifetime = spaces[index].browsingPreferences
                    .currentTabCleanupPolicy.lifetime
            else { continue }
            cleanupCurrentTabs(inSpaceAt: index, olderThan: lifetime, now: now)
        }
    }

    mutating func cleanupCurrentTabs(in spaceID: SpaceID, now: Date = .now) {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }),
            let lifetime = spaces[index].browsingPreferences
                .currentTabCleanupPolicy.lifetime
        else { return }
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
        let insertionIndex =
            spaces[spaceIndex].tabs.firstIndex { $0.placement == .current }
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
        spaces[index].archivedTabs.append(
            contentsOf: expiredTabs.map { source in
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

// MARK: - Data Retention

extension BrowserSession {
    @discardableResult
    mutating func applyDataRetentionPolicies(now: Date = .now) -> Bool {
        var removedRecords = false
        for index in spaces.indices {
            let retention = spaces[index].browsingPreferences.dataRetention
            if let lifetime = retention.history.lifetime {
                let originalCount = spaces[index].history.count
                spaces[index].history.removeAll {
                    now.timeIntervalSince($0.lastVisitedAt) > lifetime
                }
                removedRecords = removedRecords || spaces[index].history.count != originalCount
            }
            if let lifetime = retention.archive.lifetime {
                let originalCount = spaces[index].archivedTabs.count
                spaces[index].archivedTabs.removeAll {
                    now.timeIntervalSince($0.archivedAt) > lifetime
                }
                removedRecords =
                    removedRecords || spaces[index].archivedTabs.count != originalCount
            }
        }
        return removedRecords
    }
}
