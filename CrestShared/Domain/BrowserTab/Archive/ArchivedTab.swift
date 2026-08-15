import Foundation

struct ArchivedTab: Codable, Equatable, Identifiable, Sendable {
    var id: TabID { tab.id }
    var tab: BrowserTab
    var archivedAt: Date
    var reason: TabArchiveReason
}
