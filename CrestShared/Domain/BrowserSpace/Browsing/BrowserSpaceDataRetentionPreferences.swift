import Foundation

struct BrowserSpaceDataRetentionPreferences: Codable, Equatable, Sendable {
    var history: DataRetention
    var archive: DataRetention
    var downloads: DataRetention

    static let `default` = BrowserSpaceDataRetentionPreferences(
        history: .forever,
        archive: .forever,
        downloads: .forever
    )
}
