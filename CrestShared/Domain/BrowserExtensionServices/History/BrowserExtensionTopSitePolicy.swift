import Foundation

/// Ranks a Space's history into a most-visited list.
///
/// Crest stores no separate top-sites table, so the ranking is derived on
/// demand from the visit counts and recency the history rows already carry.
/// Raw visit count alone would pin a site somebody used heavily last spring
/// above one they use daily now, so counts are weighted by how recently the
/// site was last opened — the frecency shape Firefox popularized.
enum BrowserExtensionTopSitePolicy {
    /// Recency multipliers, ordered from freshest to stalest. Each pair is the
    /// inclusive age ceiling in days and the weight applied at or below it.
    static let recencyWeights: [(maximumAgeInDays: Int, weight: Int)] = [
        (4, 100),
        (14, 70),
        (31, 50),
        (90, 30),
    ]

    /// The weight applied to anything older than the last listed ceiling.
    static let staleWeight = 10

    /// The highest-scoring entries, most relevant first.
    static func topSites(
        from history: [BrowserHistoryEntry],
        limit: Int,
        now: Date
    ) -> [BrowserExtensionTopSite] {
        guard limit > 0 else { return [] }

        return
            history
            .map { entry in (entry: entry, score: score(for: entry, now: now)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.entry.lastVisitedAt != rhs.entry.lastVisitedAt {
                    return lhs.entry.lastVisitedAt > rhs.entry.lastVisitedAt
                }
                return lhs.entry.url.absoluteString < rhs.entry.url.absoluteString
            }
            .prefix(limit)
            .map { BrowserExtensionTopSite(url: $0.entry.url, title: $0.entry.title) }
    }

    /// The frecency score for one entry.
    static func score(for entry: BrowserHistoryEntry, now: Date) -> Int {
        max(1, entry.visitCount) * weight(forVisitAt: entry.lastVisitedAt, now: now)
    }

    private static func weight(forVisitAt date: Date, now: Date) -> Int {
        let ageInDays = Int(
            max(0, now.timeIntervalSince(date)) / 86_400
        )
        for step in recencyWeights where ageInDays <= step.maximumAgeInDays {
            return step.weight
        }
        return staleWeight
    }
}
