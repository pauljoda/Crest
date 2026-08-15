import Foundation

enum TabArchiveReason: String, Codable, Equatable, Sendable {
    case autoCleanup
    case closed
    case quickWindow
}
