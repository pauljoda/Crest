import Foundation

extension BrowserDownloadItemState {
    var utilityStatusText: BrowserUtilityText {
        switch self {
        case .preparing:
            .localized("Preparing…")
        case .awaitingApproval:
            .localized("Waiting for approval…")
        case .downloading:
            .localized("Downloading…")
        case .finished:
            .localized("Download")
        case .blockedAutomaticDownload:
            .localized("Blocked an automatic download from this site.")
        case .canceled(let message), .failed(let message):
            .verbatim(message)
        }
    }
}
