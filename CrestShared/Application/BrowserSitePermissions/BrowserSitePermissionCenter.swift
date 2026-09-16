import Foundation
import Observation

struct BrowserSitePermissionChange {
    var spaceID: SpaceID?
    var origin: BrowserSiteOrigin?
    var permission: BrowserSitePermission?
    var detail: String?
    var revokesAuthorization: Bool

    func affects(_ permission: BrowserSitePermission, origin: BrowserSiteOrigin, in spaceID: SpaceID) -> Bool {
        (self.spaceID == nil || self.spaceID == spaceID)
            && (self.origin == nil || self.origin == origin)
            && (self.permission == nil || self.permission == permission)
            && detail == nil
    }
}

@MainActor
protocol BrowserSitePermissionObserver: AnyObject {
    func sitePermissionsDidChange(_ change: BrowserSitePermissionChange)
}

@Observable
@MainActor
final class BrowserSitePermissionCenter {
    private struct Observer {
        weak var value: (any BrowserSitePermissionObserver)?
    }
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
    private(set) var revision: UInt64 = 0

    @ObservationIgnored private let persistence: any BrowserSitePermissionPersisting
    @ObservationIgnored private var sessionDecisions: [SpaceID: [Key: BrowserSitePermissionDecision]] = [:]
    @ObservationIgnored private var observers: [Observer] = []

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

    /// Authorization withdrawal must be synchronous: observation can coalesce
    /// a reset followed by a new grant, leaving old requests authorized.
    func addObserver(_ observer: any BrowserSitePermissionObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(Observer(value: observer))
    }

    private func notify(_ change: BrowserSitePermissionChange) {
        observers.removeAll { $0.value == nil }
        for observer in observers.compactMap(\.value) {
            observer.sitePermissionsDidChange(change)
        }
    }

    func setDecision(
        _ decision: BrowserSitePermissionDecision,
        for permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        revision &+= 1
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
        notify(BrowserSitePermissionChange(
            spaceID: spaceID, origin: origin, permission: permission, detail: detail,
            revokesAuthorization: decision != .grantPersistently && decision != .grantForSession
        ))
    }

    func reset(recordID: BrowserSitePermissionRecord.ID) {
        revision &+= 1
        let record = persistentRecords.first { $0.id == recordID }
        let count = persistentRecords.count
        persistentRecords.removeAll { $0.id == recordID }
        if persistentRecords.count != count {
            persist()
        }
        if let record {
            notify(BrowserSitePermissionChange(
                spaceID: record.spaceID, origin: record.origin, permission: record.permission,
                detail: record.detail, revokesAuthorization: true
            ))
        }
    }

    func reset(spaceID: SpaceID) {
        revision &+= 1
        sessionDecisions.removeValue(forKey: spaceID)
        let count = persistentRecords.count
        persistentRecords.removeAll { $0.spaceID == spaceID }
        if persistentRecords.count != count {
            persist()
        }
        notify(BrowserSitePermissionChange(spaceID: spaceID, revokesAuthorization: true))
    }

    func resetSession() {
        revision &+= 1
        let decisions = sessionDecisions
        sessionDecisions.removeAll()
        for (spaceID, keys) in decisions {
            for key in keys.keys {
                notify(BrowserSitePermissionChange(
                    spaceID: spaceID, origin: key.origin, permission: key.permission,
                    detail: key.detail, revokesAuthorization: true
                ))
            }
        }
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

    /// Combined capture must respect a block on either device. Existing combined
    /// grants remain a fallback for requests for just one of those devices.
    func mediaDecision(
        for media: BrowserMediaPermission,
        origin: BrowserSiteOrigin,
        in spaceID: SpaceID
    ) -> BrowserSitePermissionDecision {
        let combined = decision(for: .cameraAndMicrophone, origin: origin, in: spaceID)
        let permissions: [BrowserSitePermission] =
            media == .cameraAndMicrophone
            ? [.camera, .microphone] : [media.sitePermission]
        let decisions = permissions.map { decision(for: $0, origin: origin, in: spaceID) }
        if ([combined] + decisions).contains(.denyPersistently) { return .denyPersistently }
        if ([combined] + decisions).contains(.denyForSession) { return .denyForSession }
        if combined == .grantPersistently || combined == .grantForSession { return combined }
        if decisions.allSatisfy({ $0 == .grantPersistently }) { return .grantPersistently }
        if decisions.allSatisfy({ $0 == .grantPersistently || $0 == .grantForSession }) {
            return .grantForSession
        }
        return .ask
    }
}
