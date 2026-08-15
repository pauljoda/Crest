import Foundation

enum BrowserDownloadItemState: Equatable, Sendable {
    case preparing
    case awaitingApproval
    case downloading
    case finished
    case blockedAutomaticDownload
    case canceled(String)
    case failed(String)
}
