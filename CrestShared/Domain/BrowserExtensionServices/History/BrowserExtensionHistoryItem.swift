import Foundation

/// One `chrome.history.HistoryItem`, projected from Crest's per-Space history.
struct BrowserExtensionHistoryItem: Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let lastVisitTime: Date
    let visitCount: Int
    /// Always zero. Crest does not distinguish a typed address from a followed
    /// link, and reporting a guess here would let extensions rank on a number
    /// Crest never measured.
    let typedCount: Int

    init(
        id: UUID,
        url: URL,
        title: String,
        lastVisitTime: Date,
        visitCount: Int,
        typedCount: Int = 0
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.lastVisitTime = lastVisitTime
        self.visitCount = visitCount
        self.typedCount = typedCount
    }

    init(_ entry: BrowserHistoryEntry) {
        self.init(
            id: entry.id,
            url: entry.url,
            title: entry.title,
            lastVisitTime: entry.lastVisitedAt,
            visitCount: entry.visitCount
        )
    }
}
