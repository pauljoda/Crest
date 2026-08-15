struct BrowserCloudSyncConflictSummary: Equatable, Sendable {
    let localRecordCount: Int
    let cloudRecordCount: Int
    let localSpaceCount: Int
    let cloudSpaceCount: Int

    static func comparing(
        localRecords: [BrowserSyncRecord],
        cloudRecords: [BrowserSyncRecord]
    ) -> BrowserCloudSyncConflictSummary {
        BrowserCloudSyncConflictSummary(
            localRecordCount: localRecords.count,
            cloudRecordCount: cloudRecords.count,
            localSpaceCount: savedSpaceCount(in: localRecords),
            cloudSpaceCount: savedSpaceCount(in: cloudRecords)
        )
    }

    private static func savedSpaceCount(in records: [BrowserSyncRecord]) -> Int {
        records.filter { $0.id.kind == .space && $0.payload != nil }.count
    }
}
