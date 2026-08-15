import Foundation

struct BrowserSyncArchive: Codable, Equatable, Sendable {
    let tab: BrowserSyncTab
    var archivedAt: Date
    var reason: TabArchiveReason

    var id: TabID { tab.id }
    var spaceID: SpaceID { tab.spaceID }
}
