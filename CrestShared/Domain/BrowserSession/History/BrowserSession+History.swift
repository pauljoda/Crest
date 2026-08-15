import Foundation

extension BrowserSession {
    static let maximumHistoryEntriesPerSpace = 5_000

    mutating func recordVisit(url: URL, title: String?, at date: Date = .now) {
        guard let normalizedURL = BrowserHistoryURL.normalized(url),
              let spaceIndex = selectedSpaceIndex else { return }
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
              let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
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
        let resolvedTitle = title.flatMap { $0.isEmpty ? nil : $0 }
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
