extension BrowserCommandPaletteResults {
    static func historyResults(
        query: BrowserCommandPaletteQuery,
        space: BrowserSpace?,
        claimedURLs: Set<String>
    ) -> [BrowserCommandPaletteResult] {
        guard !query.isEmpty, let history = space?.history, !history.isEmpty else {
            return []
        }

        var candidates:
            [(
                entry: BrowserHistoryEntry,
                score: Int,
                position: Int
            )] = []
        candidates.reserveCapacity(BrowserCommandPaletteResultLimits.historyCandidates)

        for (position, entry)
            in history
            .prefix(BrowserCommandPaletteResultLimits.historyScan)
            .enumerated()
        {
            guard !Task.isCancelled else { return [] }
            guard !claimedURLs.contains(normalizedKey(entry.url)) else { continue }
            guard
                let score = BrowserCommandPaletteText.score(
                    query,
                    title: entry.title,
                    detail: entry.url.absoluteString
                )
            else { continue }
            candidates.append(
                (
                    entry,
                    score + recencyBonus(position: position, entry: entry),
                    position
                ))
            if candidates.count >= BrowserCommandPaletteResultLimits.historyCandidates {
                break
            }
        }

        return
            candidates
            .sorted { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.position < rhs.position
                    : lhs.score > rhs.score
            }
            .prefix(BrowserCommandPaletteResultLimits.history)
            .map { candidate in
                BrowserCommandPaletteResult(
                    section: .history,
                    id: "history-\(candidate.entry.id.uuidString)",
                    title: candidate.entry.title.isEmpty
                        ? (candidate.entry.url.host()
                            ?? candidate.entry.url.absoluteString)
                        : candidate.entry.title,
                    subtitle: candidate.entry.url.absoluteString,
                    symbol: "clock",
                    trailing: "Open",
                    target: .url(candidate.entry.url)
                )
            }
    }

    static func recencyBonus(
        position: Int,
        entry: BrowserHistoryEntry
    ) -> Int {
        let recency = max(
            0,
            BrowserCommandPaletteResultLimits.maximumHistoryRecencyBonus
                - position
                / BrowserCommandPaletteResultLimits.historyRecencyDecayInterval
        )
        let repetition = min(
            BrowserCommandPaletteResultLimits.maximumHistoryRepetitionBonus,
            entry.visitCount * BrowserCommandPaletteResultLimits.historyVisitBonus
        )
        return recency + repetition
    }
}
