@MainActor
extension BrowserStore: BrowserCloudSyncModelGateway {
    func cloudSyncRecords() async -> [BrowserSyncRecord] {
        guard !session.hasDisposableSeedState else { return [] }
        return syncCoordinator?.journal.records ?? []
    }

    func cloudSyncPendingRecordIDs() async -> Set<BrowserSyncRecordID> {
        guard !session.hasDisposableSeedState else { return [] }
        return syncCoordinator?.journal.pendingRecordIDs ?? []
    }

    func mergeCloudSyncRecords(_ records: [BrowserSyncRecord]) async throws {
        try mergeRemoteSyncRecords(records)
    }

    func markCloudSyncRecordsUploaded(
        _ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]
    ) async throws {
        try syncCoordinator?.markUploaded(acknowledgedVersions)
    }
}
