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
