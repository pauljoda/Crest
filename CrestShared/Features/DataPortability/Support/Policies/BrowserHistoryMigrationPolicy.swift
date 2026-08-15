import Foundation

enum BrowserHistoryMigrationPolicy {
    static func normalizedHistory(
        from records: [BrowserHistorySQLiteRecord],
        source: BrowserHistoryMigrationSource
    ) -> [BrowserHistoryEntry] {
        var entriesByURL: [URL: BrowserHistoryEntry] = [:]
        for record in records {
            guard let url = sanitizedHistoryURL(record.url) else { continue }
            let firstVisitedAt = date(
                from: min(record.firstVisit, record.lastVisit),
                source: source
            )
            let lastVisitedAt = date(
                from: max(record.firstVisit, record.lastVisit),
                source: source
            )
            guard firstVisitedAt.timeIntervalSinceReferenceDate.isFinite,
                lastVisitedAt.timeIntervalSinceReferenceDate.isFinite
            else { continue }
            let title = normalizedTitle(record.title, fallback: url.host ?? url.absoluteString)
            let visitCount = max(1, min(record.visitCount, 1_000_000_000))

            if let existing = entriesByURL[url] {
                entriesByURL[url] = BrowserHistoryEntry(
                    url: url,
                    title: lastVisitedAt >= existing.lastVisitedAt ? title : existing.title,
                    firstVisitedAt: min(firstVisitedAt, existing.firstVisitedAt),
                    lastVisitedAt: max(lastVisitedAt, existing.lastVisitedAt),
                    visitCount: min(1_000_000_000, existing.visitCount + visitCount)
                )
            } else {
                entriesByURL[url] = BrowserHistoryEntry(
                    url: url,
                    title: title,
                    firstVisitedAt: firstVisitedAt,
                    lastVisitedAt: lastVisitedAt,
                    visitCount: visitCount
                )
            }
        }
        return entriesByURL.values
            .sorted {
                if $0.lastVisitedAt != $1.lastVisitedAt {
                    return $0.lastVisitedAt > $1.lastVisitedAt
                }
                return $0.url.absoluteString < $1.url.absoluteString
            }
            .prefix(BrowserSession.maximumHistoryEntriesPerSpace)
            .map(\.self)
    }

    private static func date(
        from rawValue: Double,
        source: BrowserHistoryMigrationSource
    ) -> Date {
        switch source {
        case .safari:
            Date(timeIntervalSinceReferenceDate: rawValue)
        case .chrome, .arc:
            Date(timeIntervalSince1970: rawValue / 1_000_000 - 11_644_473_600)
        case .firefox:
            Date(timeIntervalSince1970: rawValue / 1_000_000)
        }
    }

    private static func sanitizedHistoryURL(_ source: String) -> URL? {
        guard source.count <= 8_192,
            let candidate = URL(string: source),
            var components = URLComponents(
                url: candidate,
                resolvingAgainstBaseURL: false
            ),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false
        else { return nil }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.fragment = nil
        return components.url
    }

    private static func normalizedTitle(_ source: String, fallback: String) -> String {
        let collapsed = source.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let value = collapsed.isEmpty ? fallback : collapsed
        return String(value.prefix(4_096))
    }
}
