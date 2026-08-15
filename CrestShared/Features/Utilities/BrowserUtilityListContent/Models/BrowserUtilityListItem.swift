import Foundation

enum BrowserUtilityListItem: Identifiable, Sendable {
    case archive(ArchivedTab)
    case history(BrowserHistoryEntry)
    case download(BrowserDownloadItem)

    var id: BrowserUtilityListItemID {
        switch self {
        case .archive(let item): .archive(item.id)
        case .history(let item): .history(item.id)
        case .download(let item): .download(item.id)
        }
    }

    var date: Date {
        switch self {
        case .archive(let item): item.archivedAt
        case .history(let item): item.lastVisitedAt
        case .download(let item): item.createdAt
        }
    }
}
