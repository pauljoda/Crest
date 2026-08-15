import Foundation

enum BrowserUtilityDownloadAction {
    case open(UUID, BrowserUtilityDownloadDestination)
    case retry(UUID)
    case cancel(UUID)
    case clear(UUID)
}
