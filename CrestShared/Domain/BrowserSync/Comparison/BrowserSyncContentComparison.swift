import Foundation

enum BrowserSyncContentComparison {
    static func hasEquivalentContent(
        localRecords: [BrowserSyncRecord],
        remoteRecords: [BrowserSyncRecord]
    ) -> Bool {
        let local = contentSnapshot(localRecords)
        let remote = contentSnapshot(remoteRecords)
        return local == remote
    }

    private struct Content: Equatable {
        let spaceID: SpaceID
        let payload: BrowserSyncPayload?
        let tombstone: BrowserSyncTombstone?
    }

    private static func contentSnapshot(
        _ records: [BrowserSyncRecord]
    ) -> [BrowserSyncRecordID: Content] {
        Dictionary(
            records.map { record in
                (
                    record.id,
                    Content(
                        spaceID: record.spaceID,
                        payload: record.payload,
                        tombstone: record.tombstone
                    )
                )
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }
}
