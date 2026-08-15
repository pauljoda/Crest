import CloudKit

struct BrowserCloudSnapshotLoader: Sendable {
    let database: CKDatabase
    private let codec = BrowserCloudRecordCodec()

    /// Reads every record in Crest's zone, one record at a time.
    ///
    /// A single record this build cannot read must not decide the whole snapshot:
    /// the snapshot is what account reconciliation and both conflict answers
    /// compare, so failing here would leave somebody unable to choose between
    /// their devices at all.
    func load() async throws -> [BrowserSyncRecord] {
        var token: CKServerChangeToken?
        var recordsByID: [BrowserSyncRecordID: BrowserSyncRecord] = [:]
        var hasMore = true
        while hasMore {
            let changes = try await database.recordZoneChanges(
                inZoneWith: BrowserCloudRecordCodec.zoneID,
                since: token,
                desiredKeys: nil,
                resultsLimit: nil
            )
            var fetched: [CKRecord] = []
            for result in changes.modificationResultsByID.values {
                // A fetch that failed is still an incomplete snapshot, and an
                // incomplete snapshot must never drive an overwrite decision.
                fetched.append(try result.get().record)
            }
            for decoded in BrowserCloudSyncEngine.fetchedBatch(
                decoding: fetched,
                using: codec
            ).records {
                recordsByID[decoded.id] = decoded
            }
            for deletion in changes.deletions {
                guard
                    let id = BrowserSyncRecordID(
                        recordName: deletion.recordID.recordName
                    )
                else { continue }
                recordsByID.removeValue(forKey: id)
            }
            token = changes.changeToken
            hasMore = changes.moreComing
        }
        return recordsByID.values.sorted { $0.id.recordName < $1.id.recordName }
    }
}
