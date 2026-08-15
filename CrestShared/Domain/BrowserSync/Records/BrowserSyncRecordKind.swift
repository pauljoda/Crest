import Foundation

enum BrowserSyncRecordKind: String, Codable, CaseIterable, Equatable, Sendable {
    case space
    case folder
    case tab
    case history
    case archive
}
