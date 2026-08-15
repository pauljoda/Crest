import Foundation

extension Array where Element == BrowserSyncRecord {
    func sortedByRecordName() -> [BrowserSyncRecord] {
        sorted { $0.id.recordName < $1.id.recordName }
    }
}
