import Foundation
import Observation

@Observable
@MainActor
final class BrowserSitePermissionCenter {
    private struct Key: Hashable {
        let origin: BrowserSiteOrigin
        let permission: BrowserSitePermission
        let detail: String?

        init(
            origin: BrowserSiteOrigin,
            permission: BrowserSitePermission,
            detail: String? = nil
        ) {
            self.origin = origin
            self.permission = permission
            self.detail = detail
        }

        /// The site-wide rule this key falls back to, or nil when it already is
        /// that rule.
        var siteWide: Key? {
            guard detail != nil else { return nil }
            return Key(origin: origin, permission: permission)
        }

        func matches(_ record: BrowserSitePermissionRecord, in spaceID: SpaceID) -> Bool {
            record.spaceID == spaceID
                && record.origin == origin
                && record.permission == permission
                && record.detail == detail
        }
    }

    private(set) var persistentRecords: [BrowserSitePermissionRecord]

    @ObservationIgnored private let persistence: any BrowserSitePermissionPersisting
    @ObservationIgnored private var sessionDecisions: [SpaceID: [Key: BrowserSitePermissionDecision]] = [:]

    init(persistence: any BrowserSitePermissionPersisting) {
        self.persistence = persistence
        persistentRecords = persistence.load().filter {
            BrowserSitePermissionDecisionPersistencePolicy.isPersistent($0.decision)
        }
    }

    /// The choice that applies to one request. `detail` narrows a capability a
    /// site can ask for more than one way; the narrowest saved choice wins, and a
    /// site-wide rule for the same capability answers whatever it does not cover.
    func decision(
        for permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID
    ) -> BrowserSitePermissionDecision {
        let key = Key(origin: origin, permission: permission, detail: detail)
        for candidate in [key, key.siteWide].compactMap(\.self) {
            if let sessionDecision = sessionDecisions[spaceID]?[candidate] {
                return sessionDecision
            }
            if let record = persistentRecords.first(where: {
                candidate.matches($0, in: spaceID)
            }) {
                return record.decision
            }
        }
        return .ask
    }

    func records(in spaceID: SpaceID) -> [BrowserSitePermissionRecord] {
        persistentRecords
            .filter { $0.spaceID == spaceID }
            .sorted(by: BrowserSitePermissionRecordOrderingPolicy.areInIncreasingOrder)
    }

    func setDecision(
        _ decision: BrowserSitePermissionDecision,
        for permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        let key = Key(origin: origin, permission: permission, detail: detail)
        switch decision {
        case .ask:
            sessionDecisions[spaceID]?.removeValue(forKey: key)
            removePersistentRecord(for: key, in: spaceID)
        case .grantForSession, .denyForSession:
            sessionDecisions[spaceID, default: [:]][key] = decision
        case .grantPersistently, .denyPersistently:
            sessionDecisions[spaceID]?.removeValue(forKey: key)
            if let index = persistentRecords.firstIndex(where: {
                key.matches($0, in: spaceID)
            }) {
                persistentRecords[index].decision = decision
                persistentRecords[index].modifiedAt = date
            } else {
                persistentRecords.append(
                    BrowserSitePermissionRecord(
                        spaceID: spaceID,
                        origin: origin,
                        permission: permission,
                        detail: detail,
                        decision: decision,
                        modifiedAt: date
                    )
                )
            }
            persist()
        }
    }

    func reset(recordID: BrowserSitePermissionRecord.ID) {
        let count = persistentRecords.count
        persistentRecords.removeAll { $0.id == recordID }
        if persistentRecords.count != count {
            persist()
        }
    }

    func reset(spaceID: SpaceID) {
        sessionDecisions.removeValue(forKey: spaceID)
        let count = persistentRecords.count
        persistentRecords.removeAll { $0.spaceID == spaceID }
        if persistentRecords.count != count {
            persist()
        }
    }

    func resetSession() {
        sessionDecisions.removeAll()
    }

    private func removePersistentRecord(for key: Key, in spaceID: SpaceID) {
        let count = persistentRecords.count
        persistentRecords.removeAll { key.matches($0, in: spaceID) }
        if persistentRecords.count != count {
            persist()
        }
    }

    private func persist() {
        persistence.save(persistentRecords)
    }
}
