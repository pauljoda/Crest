import Foundation

struct BrowserSyncRecord: Codable, Equatable, Sendable {
    let id: BrowserSyncRecordID
    let spaceID: SpaceID
    let version: BrowserSyncVersion
    let payload: BrowserSyncPayload?
    let tombstone: BrowserSyncTombstone?
    private let payloadAdditions: BrowserSyncJSON?
    private let tombstoneAdditions: BrowserSyncJSON?

    init(id: BrowserSyncRecordID, spaceID: SpaceID, version: BrowserSyncVersion,
         payload: BrowserSyncPayload?, tombstone: BrowserSyncTombstone?,
         payloadAdditions: BrowserSyncJSON? = nil, tombstoneAdditions: BrowserSyncJSON? = nil) {
        self.id = id; self.spaceID = spaceID; self.version = version
        self.payload = payload; self.tombstone = tombstone; self.payloadAdditions = payloadAdditions
        self.tombstoneAdditions = tombstoneAdditions
    }

    private enum CodingKeys: String, CodingKey { case id, spaceID, version, payload, tombstone }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(BrowserSyncRecordID.self, forKey: .id)
        spaceID = try values.decode(SpaceID.self, forKey: .spaceID)
        version = try values.decode(BrowserSyncVersion.self, forKey: .version)
        payload = try values.decodeIfPresent(BrowserSyncPayload.self, forKey: .payload)
        tombstone = try values.decodeIfPresent(BrowserSyncTombstone.self, forKey: .tombstone)
        if let payload {
            let raw = try values.decode(BrowserSyncJSON.self, forKey: .payload)
            payloadAdditions = try raw.additions(to: .encoded(payload))
        } else { payloadAdditions = nil }
        if let tombstone {
            let raw = try values.decode(BrowserSyncJSON.self, forKey: .tombstone)
            tombstoneAdditions = try raw.additions(to: .encoded(tombstone))
        } else { tombstoneAdditions = nil }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(spaceID, forKey: .spaceID)
        try values.encode(version, forKey: .version)
        // The journal/ABI format uses reference-date seconds. Cloud payloads
        // explicitly use Unix seconds through encodedPayload(using:).
        if let payload, payloadAdditions != nil {
            try values.encode(try BrowserSyncJSON.encoded(payload).adding(payloadAdditions), forKey: .payload)
        } else { try values.encodeIfPresent(payload, forKey: .payload) }
        if let tombstone, tombstoneAdditions != nil {
            try values.encode(try BrowserSyncJSON.encoded(tombstone).adding(tombstoneAdditions), forKey: .tombstone)
        } else { try values.encodeIfPresent(tombstone, forKey: .tombstone) }
    }

    /// TRANSITIONAL until slice 8c moves the payload codec into the core: the
    /// payload or tombstone as the journal holds it, spelled as
    /// `encode(to:)` spells it with the default encoder. A record that holds
    /// both or neither has no body, which the core refuses as malformed.
    var journalBody: Data {
        get throws {
            let encoder = JSONEncoder()
            switch (payload, tombstone) {
            case (let payload?, nil):
                guard payloadAdditions != nil else { return try encoder.encode(payload) }
                return try encoder.encode(BrowserSyncJSON.encoded(payload).adding(payloadAdditions))
            case (nil, let tombstone?):
                guard tombstoneAdditions != nil else { return try encoder.encode(tombstone) }
                return try encoder.encode(BrowserSyncJSON.encoded(tombstone).adding(tombstoneAdditions))
            default:
                return Data()
            }
        }
    }

    func encodedPayload(using encoder: JSONEncoder) throws -> Data? {
        guard let payload else { return nil }
        guard payloadAdditions != nil else { return try encoder.encode(payload) }
        return try encoder.encode(BrowserSyncJSON.encoded(payload, using: encoder).adding(payloadAdditions))
    }

    func encodedTombstone(using encoder: JSONEncoder) throws -> Data? {
        guard let tombstone else { return nil }
        guard tombstoneAdditions != nil else { return try encoder.encode(tombstone) }
        return try encoder.encode(BrowserSyncJSON.encoded(tombstone, using: encoder).adding(tombstoneAdditions))
    }

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
        reason: SyncDeletionReason,
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
    let reason: SyncDeletionReason
    let deletedAt: Date
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

// MARK: - Core records

extension SyncRecord {
    /// TRANSITIONAL until slice 8c: `record` as the core takes it.
    init(browser record: BrowserSyncRecord) throws {
        self.init(
            kind: SyncRecordKind(browser: record.id.kind), id: record.id.value, spaceID: record.spaceID.rawValue,
            version: SyncVersion(clock: record.version.logicalClock, deviceID: record.version.deviceID),
            body: try record.journalBody, isTombstone: record.payload == nil)
    }
}

extension BrowserSyncRecord {
    /// TRANSITIONAL until slice 8c: `record`, which the core answered in the
    /// journal's form, as the CloudKit codec reads it. It decodes exactly as
    /// the journal's records did, so the fields this build does not know ride
    /// along.
    init(core record: SyncRecord) throws {
        guard let kind = BrowserSyncRecordKind(rawValue: record.kind.name) else {
            throw BrowserSyncError.invalidRecord(record.kind.name)
        }
        let decoder = JSONDecoder()
        let raw = try decoder.decode(BrowserSyncJSON.self, from: record.body)
        let id = BrowserSyncRecordID(kind: kind, value: record.id)
        let spaceID = SpaceID(rawValue: record.spaceID)
        let version = BrowserSyncVersion(logicalClock: record.version.clock, deviceID: record.version.deviceID)
        if record.isTombstone {
            let tombstone = try decoder.decode(BrowserSyncTombstone.self, from: record.body)
            self.init(
                id: id, spaceID: spaceID, version: version, payload: nil, tombstone: tombstone,
                tombstoneAdditions: try raw.additions(to: .encoded(tombstone)))
        } else {
            let payload = try decoder.decode(BrowserSyncPayload.self, from: record.body)
            self.init(
                id: id, spaceID: spaceID, version: version, payload: payload, tombstone: nil,
                payloadAdditions: try raw.additions(to: .encoded(payload)))
        }
    }
}

extension SyncRecordKind {
    /// TRANSITIONAL until slice 8c: the kind `kind` names.
    init(browser kind: BrowserSyncRecordKind) {
        self =
            switch kind {
            case .space: .space
            case .folder: .folder
            case .tab: .tab
            case .history: .history
            case .archive: .archive
            }
    }
}
