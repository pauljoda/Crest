import Foundation

struct BrowserSyncHistory: Codable, Equatable, Sendable {
    let id: UUID
    let spaceID: SpaceID
    let url: URL
    var title: String
    let firstVisitedAt: Date
    var lastVisitedAt: Date
    var visitCount: Int
}
