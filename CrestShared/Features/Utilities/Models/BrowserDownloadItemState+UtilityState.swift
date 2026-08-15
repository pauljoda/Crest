extension BrowserDownloadItemState {
    var isInProgress: Bool {
        switch self {
        case .preparing, .awaitingApproval, .downloading:
            true
        case .finished, .blockedAutomaticDownload, .canceled, .failed:
            false
        }
    }

    var needsAttention: Bool {
        switch self {
        case .failed, .blockedAutomaticDownload:
            true
        case .preparing, .awaitingApproval, .downloading, .finished, .canceled:
            false
        }
    }
}
