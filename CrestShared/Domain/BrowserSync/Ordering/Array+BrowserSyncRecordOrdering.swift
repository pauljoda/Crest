import Foundation

extension Array where Element == BrowserSyncRecord {
    func sortedByRecordName() -> [BrowserSyncRecord] {
        // Formatting a UUID for every comparison amplifies full-journal work.
        // Cache each name once while preserving the existing wire-name order.
        map { (name: $0.id.recordName, record: $0) }
            .sorted { $0.name < $1.name }
            .map(\.record)
    }
}
