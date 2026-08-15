import Foundation

extension BrowserSession {
    @discardableResult
    mutating func applyDataRetentionPolicies(now: Date = .now) -> Bool {
        var removedRecords = false
        for index in spaces.indices {
            let retention = spaces[index].browsingPreferences.dataRetention
            if let lifetime = retention.history.lifetime {
                let originalCount = spaces[index].history.count
                spaces[index].history.removeAll {
                    now.timeIntervalSince($0.lastVisitedAt) > lifetime
                }
                removedRecords = removedRecords || spaces[index].history.count != originalCount
            }
            if let lifetime = retention.archive.lifetime {
                let originalCount = spaces[index].archivedTabs.count
                spaces[index].archivedTabs.removeAll {
                    now.timeIntervalSince($0.archivedAt) > lifetime
                }
                removedRecords =
                    removedRecords || spaces[index].archivedTabs.count != originalCount
            }
        }
        return removedRecords
    }
}
