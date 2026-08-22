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
            guard case .tab(let tab)? = record.payload else { return nil }
            return (record, tab)
        }

        for (tabRecord, tab) in tabs {
            let archiveID = BrowserSyncRecordID(kind: .archive, value: tab.id.rawValue)
            guard let archiveRecord = byID[archiveID],
                case .archive(let archive)? = archiveRecord.payload
            else { continue }

            let activeTabWins: Bool
            if tab.placement != .current {
                // A routine close/archive is not proof that somebody deleted a
                // pinned or saved tab. Only its explicit tab tombstone may
                // remove protected content; until then the live record wins.
                activeTabWins = true
            } else if archive.reason.isExplicitDeletion {
                // The archive is only the deletion's audit trail. It cannot
                // remove the live tab before the explicit tab tombstone arrives
                // in what may be a later CloudKit batch.
                activeTabWins = true
            } else if archive.reason == .autoCleanup {
                activeTabWins = tab.lastActivatedAt > archive.archivedAt
            } else {
                activeTabWins = archiveRecord.version < tabRecord.version
            }
            if activeTabWins {
                byID.removeValue(forKey: archiveID)
            } else {
                byID.removeValue(forKey: tabRecord.id)
            }
        }
        return Array(byID.values).sortedByRecordName()
    }
}
