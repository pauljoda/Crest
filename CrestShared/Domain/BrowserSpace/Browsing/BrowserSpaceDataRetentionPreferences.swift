import Foundation

struct BrowserSpaceDataRetentionPreferences: Codable, Equatable, Sendable {
    var history: BrowserDataRetentionDuration
    var archive: BrowserDataRetentionDuration
    var downloads: BrowserDataRetentionDuration

    static let `default` = BrowserSpaceDataRetentionPreferences(
        history: .forever,
        archive: .forever,
        downloads: .forever
    )
}
