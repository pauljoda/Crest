protocol BrowserCloudSyncModelGateway: Sendable {
    func cloudSyncRecords() async -> [BrowserSyncRecord]
    func cloudSyncPendingRecordIDs() async -> Set<BrowserSyncRecordID>
    func mergeCloudSyncRecords(_ records: [BrowserSyncRecord]) async throws
    func markCloudSyncRecordsUploaded(
        _ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]
    ) async throws
}
