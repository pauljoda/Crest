protocol BrowserCloudSyncModelGateway: Sendable {
    /// Every record the device's sync journal holds. Throws
    /// `BrowserSyncError.unreadableJournal` while this build cannot read it.
    func cloudSyncRecords() async throws -> [BrowserSyncRecord]
    /// The records that wait to upload. Throws
    /// `BrowserSyncError.unreadableJournal` while this build cannot read the
    /// journal.
    func cloudSyncPendingRecordIDs() async throws -> Set<BrowserSyncRecordID>
    /// Merges downloaded records. Refused while this build cannot read the
    /// journal.
    func mergeCloudSyncRecords(_ records: [BrowserSyncRecord]) async throws
    func markCloudSyncRecordsUploaded(
        _ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]
    ) async throws
}
