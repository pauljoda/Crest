enum BrowserCloudSyncStatus: Equatable, Sendable {
    case stopped
    case syncing
    case idle
    case pausedForAccountConfirmation
    case failed(String)
}
