import Foundation

enum BrowserUtilityListItemID: Hashable, Sendable {
    case archive(TabID)
    case history(UUID)
    case download(UUID)
}
