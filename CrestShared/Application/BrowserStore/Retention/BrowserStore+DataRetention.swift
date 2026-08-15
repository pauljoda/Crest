import Foundation

extension BrowserStore {
    func updateDataRetentionPreferences(
        _ retention: BrowserSpaceDataRetentionPreferences,
        in spaceID: SpaceID,
        now: Date = .now
    ) {
        guard var preferences = session.space(id: spaceID)?.browsingPreferences,
            preferences.dataRetention != retention
        else {
            return
        }
        preferences.dataRetention = retention
        session.updateBrowsingPreferences(preferences, in: spaceID)
        let removedRecords = session.applyDataRetentionPolicies(now: now)
        persist(
            deletionReason: removedRecords ? .retention : .superseded,
            scope: removedRecords ? .everything : .core
        )
    }
}
