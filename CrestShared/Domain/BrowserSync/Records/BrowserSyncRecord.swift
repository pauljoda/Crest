import Foundation

struct BrowserSyncRecord: Codable, Equatable, Sendable {
    let id: BrowserSyncRecordID
    let spaceID: SpaceID
    let version: BrowserSyncVersion
    let payload: BrowserSyncPayload?
    let tombstone: BrowserSyncTombstone?

    static func save(_ payload: BrowserSyncPayload, version: BrowserSyncVersion) -> BrowserSyncRecord {
        BrowserSyncRecord(
            id: payload.recordID,
            spaceID: payload.spaceID,
            version: version,
            payload: payload,
            tombstone: nil
        )
    }

    static func delete(
        id: BrowserSyncRecordID,
        spaceID: SpaceID,
        version: BrowserSyncVersion,
        reason: BrowserSyncTombstoneReason,
        at date: Date
    ) -> BrowserSyncRecord {
        BrowserSyncRecord(
            id: id,
            spaceID: spaceID,
            version: version,
            payload: nil,
            tombstone: BrowserSyncTombstone(reason: reason, deletedAt: date)
        )
    }

    func validate() throws {
        guard (payload == nil) != (tombstone == nil) else {
            throw BrowserSyncError.invalidRecord(id.recordName)
        }
        if let payload {
            guard payload.recordID == id, payload.spaceID == spaceID else {
                throw BrowserSyncError.recordIdentityMismatch(id.recordName)
            }
            try payload.validate()
        } else if id.kind == .space, id.value != spaceID.rawValue {
            throw BrowserSyncError.recordIdentityMismatch(id.recordName)
        }
    }
}

struct BrowserSyncRecordID: Codable, Hashable, Sendable {
    let kind: BrowserSyncRecordKind
    let value: UUID

    init(kind: BrowserSyncRecordKind, value: UUID) {
        self.kind = kind
        self.value = value
    }

    init?(recordName: String) {
        let parts = recordName.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let kind = BrowserSyncRecordKind(rawValue: String(parts[0])),
            let value = UUID(uuidString: String(parts[1]))
        else { return nil }
        self.init(kind: kind, value: value)
    }

    var recordName: String {
        "\(kind.rawValue):\(value.uuidString.lowercased())"
    }
}

enum BrowserSyncRecordKind: String, Codable, CaseIterable, Equatable, Sendable {
    case space
    case folder
    case tab
    case history
    case archive
}

struct BrowserSyncTombstone: Codable, Equatable, Sendable {
    let reason: BrowserSyncTombstoneReason
    let deletedAt: Date
}

enum BrowserSyncTombstoneReason: String, Codable, Equatable, Sendable {
    case explicitDelete
    case superseded
    case retention
}

struct BrowserSyncVersion: Codable, Equatable, Comparable, Sendable {
    let logicalClock: UInt64
    let deviceID: UUID

    static func < (lhs: BrowserSyncVersion, rhs: BrowserSyncVersion) -> Bool {
        if lhs.logicalClock != rhs.logicalClock {
            return lhs.logicalClock < rhs.logicalClock
        }
        return lhs.deviceID.uuidString < rhs.deviceID.uuidString
    }
}
