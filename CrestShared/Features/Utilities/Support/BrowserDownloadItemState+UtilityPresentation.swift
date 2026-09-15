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
            .localized(
                "Automatic download blocked. Use Allow Download to retry, or change Automatic Downloads in this site’s permissions."
            )
        case .canceled(let message), .failed(let message):
            .verbatim(message)
        }
    }
}
