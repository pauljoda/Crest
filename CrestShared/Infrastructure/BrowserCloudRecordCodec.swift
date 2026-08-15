import CloudKit
import Foundation

struct BrowserCloudRecordCodec: Sendable {
    static let zoneName = "CrestPrivate"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName)
    static let recordZone = CKRecordZone(zoneID: zoneID)

    func encode(
        _ source: BrowserSyncRecord,
        reusing baseRecord: CKRecord? = nil
    ) throws -> CKRecord {
        try source.validate()
        let recordID = CKRecord.ID(recordName: source.id.recordName, zoneID: Self.zoneID)
        let recordType = Self.recordType(for: source.id.kind)
        let record: CKRecord
        if let baseRecord {
            guard baseRecord.recordID == recordID, baseRecord.recordType == recordType else {
                throw BrowserCloudRecordCodecError.mismatchedBaseRecord(source.id.recordName)
            }
            record = baseRecord
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record[Field.schemaVersion] = NSNumber(value: BrowserSyncJournal.currentSchemaVersion)
        record[Field.spaceID] = source.spaceID.rawValue.uuidString.lowercased() as CKRecordValue
        record[Field.logicalClock] = NSNumber(value: source.version.logicalClock)
        record[Field.deviceID] = source.version.deviceID.uuidString.lowercased() as CKRecordValue

        if source.id.kind == .space {
            record[Field.spaceReference] = nil
        } else {
            let spaceRecordID = CKRecord.ID(
                recordName: BrowserSyncRecordID(
                    kind: .space,
                    value: source.spaceID.rawValue
                ).recordName,
                zoneID: Self.zoneID
            )
            record[Field.spaceReference] = CKRecord.Reference(recordID: spaceRecordID, action: .none)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .secondsSince1970
            if let payload = source.payload {
                record.encryptedValues[Field.payload] = try encoder.encode(payload) as CKRecordValue
                record.encryptedValues[Field.tombstone] = nil
            } else if let tombstone = source.tombstone {
                record.encryptedValues[Field.payload] = nil
                record.encryptedValues[Field.tombstone] = try encoder.encode(tombstone) as CKRecordValue
            }
        } catch {
            throw BrowserCloudRecordCodecError.payloadEncodingFailed
        }
        return record
    }

    func decode(_ record: CKRecord) throws -> BrowserSyncRecord {
        guard record.recordID.zoneID == Self.zoneID else {
            throw BrowserCloudRecordCodecError.unexpectedZone(record.recordID.zoneID.zoneName)
        }
        guard let kind = Self.kind(for: record.recordType) else {
            throw BrowserCloudRecordCodecError.unexpectedRecordType(record.recordType)
        }
        let id = try Self.recordID(from: record.recordID.recordName, expectedKind: kind)
        guard let schema = (record[Field.schemaVersion] as? NSNumber)?.intValue else {
            throw BrowserCloudRecordCodecError.missingField(Field.schemaVersion)
        }
        // A record written by an older schema still decodes. Only a newer one is
        // refused, and the engine skips just that record rather than losing the
        // batch it arrived in, so one record from a newer build cannot stop an
        // older build from syncing.
        guard (1...BrowserSyncJournal.currentSchemaVersion).contains(schema) else {
            throw BrowserSyncError.unsupportedSchema(schema)
        }
        guard let spaceIDString = record[Field.spaceID] as? String,
            let spaceUUID = UUID(uuidString: spaceIDString)
        else {
            throw BrowserCloudRecordCodecError.invalidField(Field.spaceID)
        }
        guard let clock = (record[Field.logicalClock] as? NSNumber)?.uint64Value else {
            throw BrowserCloudRecordCodecError.missingField(Field.logicalClock)
        }
        guard let deviceIDString = record[Field.deviceID] as? String,
            let deviceID = UUID(uuidString: deviceIDString)
        else {
            throw BrowserCloudRecordCodecError.invalidField(Field.deviceID)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payloadData = record.encryptedValues[Field.payload] as? Data
        let tombstoneData = record.encryptedValues[Field.tombstone] as? Data
        guard (payloadData == nil) != (tombstoneData == nil) else {
            throw BrowserCloudRecordCodecError.invalidField("payload/tombstone")
        }

        let payload: BrowserSyncPayload?
        let tombstone: BrowserSyncTombstone?
        do {
            payload = try payloadData.map { try decoder.decode(BrowserSyncPayload.self, from: $0) }
            tombstone = try tombstoneData.map { try decoder.decode(BrowserSyncTombstone.self, from: $0) }
        } catch {
            throw BrowserCloudRecordCodecError.payloadDecodingFailed
        }

        let result = BrowserSyncRecord(
            id: id,
            spaceID: SpaceID(rawValue: spaceUUID),
            version: BrowserSyncVersion(logicalClock: clock, deviceID: deviceID),
            payload: payload,
            tombstone: tombstone
        )
        try result.validate()
        return result
    }

    private enum Field {
        static let schemaVersion = "schemaVersion"
        static let spaceID = "spaceID"
        static let logicalClock = "logicalClock"
        static let deviceID = "deviceID"
        static let payload = "payload"
        static let tombstone = "tombstone"
        static let spaceReference = "space"
    }

    private static func recordType(for kind: BrowserSyncRecordKind) -> CKRecord.RecordType {
        switch kind {
        case .space: "CrestSpace"
        case .folder: "CrestFolder"
        case .tab: "CrestTab"
        case .history: "CrestHistory"
        case .archive: "CrestArchive"
        }
    }

    private static func kind(for recordType: CKRecord.RecordType) -> BrowserSyncRecordKind? {
        switch recordType {
        case "CrestSpace": .space
        case "CrestFolder": .folder
        case "CrestTab": .tab
        case "CrestHistory": .history
        case "CrestArchive": .archive
        default: nil
        }
    }

    private static func recordID(
        from recordName: String,
        expectedKind: BrowserSyncRecordKind
    ) throws -> BrowserSyncRecordID {
        guard let id = BrowserSyncRecordID(recordName: recordName),
            id.kind == expectedKind
        else {
            throw BrowserCloudRecordCodecError.malformedRecordName(recordName)
        }
        return id
    }
}
