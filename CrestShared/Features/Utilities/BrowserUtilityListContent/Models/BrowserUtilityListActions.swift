import Foundation

enum BrowserUtilityDownloadAction {
    case open(UUID, BrowserUtilityDownloadDestination)
    case retry(UUID)
    case cancel(UUID)
    case clear(UUID)
}

struct BrowserUtilityListActions {
    var restoreArchivedTab: (TabID, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
    var openHistoryEntry: (BrowserHistoryEntry, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
    var downloadDestinations: [BrowserUtilityDownloadDestination] = []
    var performDownloadAction: (BrowserUtilityDownloadAction, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
}
