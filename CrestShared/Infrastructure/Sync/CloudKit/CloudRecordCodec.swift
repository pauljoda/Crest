import CloudKit
import Foundation

struct BrowserCloudRecordCodec: Sendable {
    /// Cloud payload compatibility is independent of the local journal format.
    static let currentSchemaVersion = 3

    static let zoneName = BrowserCloudSyncConfiguration.defaultZoneName
    static let zoneID = CKRecordZone.ID(zoneName: zoneName)
    let recordZoneID: CKRecordZone.ID
    var recordZone: CKRecordZone { CKRecordZone(zoneID: recordZoneID) }

    init(zoneName: String = Self.zoneName) {
        recordZoneID = CKRecordZone.ID(zoneName: zoneName)
    }

    func encode(
        _ source: BrowserSyncRecord,
        reusing baseRecord: CKRecord? = nil
    ) throws -> CKRecord {
        try source.validate()
        let recordID = CKRecord.ID(recordName: source.id.recordName, zoneID: recordZoneID)
        let recordType = Self.recordType(for: source.id.kind)
        let record: CKRecord
        if let baseRecord {
            guard baseRecord.recordID == recordID, baseRecord.recordType == recordType else {
                throw BrowserCloudRecordCodecError.mismatchedBaseRecord(source.id.recordName)
            }
            if let schema = (baseRecord[Field.schemaVersion] as? NSNumber)?.intValue,
                schema > Self.currentSchemaVersion
            {
                throw BrowserSyncError.unsupportedSchema(schema)
            }
            record = baseRecord
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record[Field.schemaVersion] = NSNumber(value: Self.requiredSchemaVersion(for: source))
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
                zoneID: recordZoneID
            )
            record[Field.spaceReference] = CKRecord.Reference(recordID: spaceRecordID, action: .none)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .secondsSince1970
            if source.payload != nil {
                record.encryptedValues[Field.payload] = try source.encodedPayload(using: encoder) as CKRecordValue?
                record.encryptedValues[Field.tombstone] = nil
            } else if source.tombstone != nil {
                record.encryptedValues[Field.payload] = nil
                record.encryptedValues[Field.tombstone] = try source.encodedTombstone(using: encoder) as CKRecordValue?
            }
        } catch {
            throw BrowserCloudRecordCodecError.payloadEncodingFailed
        }
        return record
    }

    func decode(_ record: CKRecord) throws -> BrowserSyncRecord {
        guard record.recordID.zoneID == recordZoneID else {
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
        guard (1...Self.currentSchemaVersion).contains(schema) else {
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
        let payloadAdditions: BrowserSyncJSON?
        let tombstoneAdditions: BrowserSyncJSON?
        do {
            payload = try payloadData.map { try decoder.decode(BrowserSyncPayload.self, from: $0) }
            tombstone = try tombstoneData.map { try decoder.decode(BrowserSyncTombstone.self, from: $0) }
            if let payload, let payloadData {
                payloadAdditions = try JSONDecoder().decode(BrowserSyncJSON.self, from: payloadData)
                    .additions(to: .encoded(payload))
            } else { payloadAdditions = nil }
            if let tombstone, let tombstoneData {
                tombstoneAdditions = try JSONDecoder().decode(BrowserSyncJSON.self, from: tombstoneData)
                    .additions(to: .encoded(tombstone))
            } else { tombstoneAdditions = nil }
        } catch {
            throw BrowserCloudRecordCodecError.payloadDecodingFailed
        }

        let result = BrowserSyncRecord(
            id: id,
            spaceID: SpaceID(rawValue: spaceUUID),
            version: BrowserSyncVersion(logicalClock: clock, deviceID: deviceID),
            payload: payload,
            tombstone: tombstone,
            payloadAdditions: payloadAdditions,
            tombstoneAdditions: tombstoneAdditions
        )
        try result.validate()
        return result
    }

    // MARK: - Actions - Envelopes

    /// How CloudKit names the record `reference` names: its kind, then its
    /// identity in lowercase.
    func recordName(of reference: SyncRecordReference) -> String {
        "\(reference.kind.name):\(reference.id.uuidString.lowercased())"
    }

    /// The CloudKit identity of the record `reference` names, in this codec's
    /// zone.
    func recordID(for reference: SyncRecordReference) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName(of: reference), zoneID: recordZoneID)
    }

    /// The record a CloudKit identity in this codec's zone names, or nil for an
    /// identity no record of Crest's has.
    func reference(for recordID: CKRecord.ID) -> SyncRecordReference? {
        guard recordID.zoneID == recordZoneID else { return nil }
        let parts = recordID.recordName.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let kind = SyncRecordKind.named(String(parts[0])),
            let id = UUID(uuidString: String(parts[1]))
        else { return nil }
        return SyncRecordReference(kind: kind, id: id)
    }

    /// The record the cloud saved, at the version it saved, read from its
    /// envelope alone; nil for a record that is not one of Crest's.
    func uploadedRecord(_ record: CKRecord) -> UploadedRecord? {
        guard let reference = reference(for: record.recordID), record.recordType == reference.kind.cloudRecordType,
            let clock = (record[Field.logicalClock] as? NSNumber)?.uint64Value,
            let device = (record[Field.deviceID] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        return UploadedRecord(record: reference, version: SyncVersion(clock: clock, deviceID: device))
    }

    /// Older clients can keep syncing familiar records while skipping only
    /// folder locations and memberships they cannot represent. Tombstones use
    /// schema 1 so those clients can still remove a stale local copy.
    private static func requiredSchemaVersion(for record: BrowserSyncRecord) -> Int {
        switch record.payload {
        case .tab(let tab) where tab.nativeContent != nil:
            3
        case .archive(let archive) where archive.tab.nativeContent != nil:
            3
        case .folder(let folder) where folder.location == .current:
            2
        case .tab(let tab) where !tab.placement.isDurable && tab.folderID != nil:
            2
        default:
            1
        }
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
