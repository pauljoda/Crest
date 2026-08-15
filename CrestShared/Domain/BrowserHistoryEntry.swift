import Foundation

struct BrowserHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    let firstVisitedAt: Date
    var lastVisitedAt: Date
    var visitCount: Int

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        firstVisitedAt: Date,
        lastVisitedAt: Date,
        visitCount: Int = 1
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.firstVisitedAt = firstVisitedAt
        self.lastVisitedAt = lastVisitedAt
        self.visitCount = visitCount
    }
}
