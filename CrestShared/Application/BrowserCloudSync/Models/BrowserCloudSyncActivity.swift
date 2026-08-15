enum BrowserCloudSyncActivity: Equatable, Sendable {
    case fetched(recordCount: Int)
    case uploaded(recordCount: Int)
    case accountChanged
    /// Records that arrived but could not be read, so they were left in iCloud
    /// rather than applied. `requiresAppUpdate` means a newer build wrote them.
    case skippedRecords(count: Int, requiresAppUpdate: Bool)
    /// Crest's iCloud zone stopped existing because somebody removed it.
    case cloudDataRemoved
}
