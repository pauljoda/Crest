import Foundation

/// Turns a Space's history rows into `chrome.history` answers.
///
/// Both the store-backed service and the in-memory double run these functions,
/// so a fake used in a test cannot answer a query differently from the adapter
/// it stands in for.
enum BrowserExtensionHistoryQueryPolicy {
    /// Entries matching `query`, most-recent-first.
    ///
    /// Text matching follows the History list in Crest's own utility panel:
    /// a locale-aware, case- and diacritic-insensitive containment test against
    /// the title and the full URL.
    static func items(
        matching query: BrowserExtensionHistoryQuery,
        in history: [BrowserHistoryEntry]
    ) -> [BrowserExtensionHistoryItem] {
        guard query.maximumResults > 0 else { return [] }

        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return
            history
            .filter { entry in
                guard query.containsVisit(at: entry.lastVisitedAt) else {
                    return false
                }
                guard !text.isEmpty else { return true }
                return entry.title.localizedStandardContains(text)
                    || entry.url.absoluteString.localizedStandardContains(text)
            }
            .sorted { $0.lastVisitedAt > $1.lastVisitedAt }
            .prefix(query.maximumResults)
            .map(BrowserExtensionHistoryItem.init)
    }

    /// The visits Crest can attest to for `url`, oldest first.
    static func visits(
        for url: URL,
        in history: [BrowserHistoryEntry]
    ) -> [BrowserExtensionHistoryVisit] {
        guard let normalizedURL = BrowserHistoryURL.normalized(url),
            let entry = history.first(where: { $0.url == normalizedURL })
        else {
            return []
        }

        var visits = [
            BrowserExtensionHistoryVisit(
                id: "\(entry.id.uuidString).first",
                url: entry.url,
                visitTime: entry.firstVisitedAt
            )
        ]
        if entry.lastVisitedAt != entry.firstVisitedAt {
            visits.append(
                BrowserExtensionHistoryVisit(
                    id: "\(entry.id.uuidString).last",
                    url: entry.url,
                    visitTime: entry.lastVisitedAt
                )
            )
        }
        return visits
    }
}
