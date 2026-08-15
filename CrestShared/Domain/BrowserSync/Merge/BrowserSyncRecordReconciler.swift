import Foundation

enum BrowserSyncRecordReconciler {
    static func reconciledRecords(
        _ records: [BrowserSyncRecord]
    ) -> [BrowserSyncRecord] {
        var byID: [BrowserSyncRecordID: BrowserSyncRecord] = [:]
        for record in records {
            byID[record.id] = record
        }
        let tabs = byID.values.compactMap { record -> (BrowserSyncRecord, BrowserSyncTab)? in
            guard case let .tab(tab)? = record.payload else { return nil }
            return (record, tab)
        }

        for (tabRecord, tab) in tabs {
            let archiveID = BrowserSyncRecordID(kind: .archive, value: tab.id.rawValue)
            guard let archiveRecord = byID[archiveID],
                  case let .archive(archive)? = archiveRecord.payload else { continue }

            let activeTabWins = archive.reason == .autoCleanup
                ? tab.lastActivatedAt > archive.archivedAt
                : archiveRecord.version < tabRecord.version
            if activeTabWins {
                byID.removeValue(forKey: archiveID)
            } else {
                byID.removeValue(forKey: tabRecord.id)
            }
        }
        return Array(byID.values).sortedByRecordName()
    }
}
