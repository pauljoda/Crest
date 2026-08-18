import Foundation

struct BrowserSyncJournal: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumRecordCount = 250_000

    let schemaVersion: Int
    let deviceID: UUID
    private(set) var logicalClock: UInt64
    var preferences: BrowserSyncPreferences
    private(set) var records: [BrowserSyncRecord]
    private(set) var pendingRecordIDs: Set<BrowserSyncRecordID>

    init(
        deviceID: UUID = UUID(),
        preferences: BrowserSyncPreferences = .default
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.deviceID = deviceID
        logicalClock = 0
        self.preferences = preferences
        records = []
        pendingRecordIDs = []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case deviceID
        case logicalClock
        case preferences
        case records
        case pendingRecordIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw BrowserSyncError.unsupportedSchema(schemaVersion)
        }
        deviceID = try container.decode(UUID.self, forKey: .deviceID)
        logicalClock = try container.decode(UInt64.self, forKey: .logicalClock)
        preferences = try container.decode(BrowserSyncPreferences.self, forKey: .preferences)
        records = try container.decode([BrowserSyncRecord].self, forKey: .records)
        pendingRecordIDs = try container.decode(Set<BrowserSyncRecordID>.self, forKey: .pendingRecordIDs)
        guard records.count <= Self.maximumRecordCount else {
            throw BrowserSyncError.recordLimitExceeded(records.count)
        }

        var seen: Set<BrowserSyncRecordID> = []
        for record in records {
            try record.validate()
            guard seen.insert(record.id).inserted else {
                throw BrowserSyncError.duplicateRecord(record.id.recordName)
            }
            logicalClock = max(logicalClock, record.version.logicalClock)
        }
        guard pendingRecordIDs.isSubset(of: seen) else {
            throw BrowserSyncError.invalidField("pendingRecordIDs")
        }
    }

    var activeRecords: [BrowserSyncRecord] {
        BrowserSyncRecordReconciler.reconciledRecords(records).filter { $0.payload != nil }
    }

    /// Rewrites the journal so it describes `session`, tombstoning records only
    /// when the session carries evidence for why they were removed.
    ///
    /// A record whose owning Space has no record of its own is deliberately left
    /// alone. Restaging happens after every remote merge, and a fetch arrives in
    /// batches with no ordering guarantee, so a tab, folder, history, or archive
    /// record can land before the `CrestSpace` record that owns it.
    /// Materialization only builds Spaces it holds a Space record for, so those
    /// children are missing from `session` through nobody's decision. Deleting a
    /// Space is different: the Space keeps a record of its own throughout — a
    /// payload during the pass that removes it, a tombstone from then on — so an
    /// owning Space with no record at all is a parent that has not arrived yet
    /// rather than one somebody deleted. A saved tab whose folder has not arrived
    /// is held back for the same reason, and told apart the same way.
    mutating func stage(
        session: BrowserSession,
        deletionReason: BrowserSyncTombstoneReason = .explicitDelete,
        at date: Date = .now
    ) throws {
        var byID = try validatedRecordDictionary()
        let knownSpaceIDs = Self.spaceIDs(in: byID)
        let knownFolderIDs = Self.folderIDs(in: byID)
        let parentIDsByFolderID = Self.parentIDsByFolderID(in: byID)
        let archivedTabReasonsByID = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap { space in
                space.archivedTabs.map { ($0.id, $0.reason) }
            }
        )
        let desiredPayloads = try BrowserSyncProjection.payloads(
            from: session,
            preferences: preferences,
            existingRecords: Array(byID.values)
        )
        guard desiredPayloads.count <= Self.maximumRecordCount else {
            throw BrowserSyncError.recordLimitExceeded(desiredPayloads.count)
        }
        var desiredByID: [BrowserSyncRecordID: BrowserSyncPayload] = [:]
        for payload in desiredPayloads {
            guard desiredByID.updateValue(payload, forKey: payload.recordID) == nil else {
                throw BrowserSyncError.duplicateRecord(payload.recordID.recordName)
            }
        }

        for payload in desiredPayloads.sorted(by: { $0.recordID.recordName < $1.recordID.recordName }) {
            if byID[payload.recordID]?.payload == payload {
                continue
            }
            let record = BrowserSyncRecord.save(payload, version: try nextVersion())
            try record.validate()
            byID[record.id] = record
            pendingRecordIDs.insert(record.id)
        }

        let existingRecords = Array(byID.values)
        for record in existingRecords where record.payload != nil {
            guard let payload = record.payload, preferences.includes(payload) else { continue }
            guard desiredByID[record.id] == nil else { continue }
            guard knownSpaceIDs.contains(record.spaceID) else { continue }
            let ancestryHasArrived = Self.ancestryHasArrived(
                payload,
                knownFolderIDs: knownFolderIDs,
                parentIDsByFolderID: parentIDsByFolderID
            )
            guard ancestryHasArrived else { continue }
            guard
                let resolvedDeletionReason = Self.deletionReason(
                    for: payload,
                    desiredPayloadsByID: desiredByID,
                    archivedTabReasonsByID: archivedTabReasonsByID,
                    fallback: deletionReason
                )
            else { continue }
            let tombstone = BrowserSyncRecord.delete(
                id: record.id,
                spaceID: record.spaceID,
                version: try nextVersion(),
                reason: resolvedDeletionReason,
                at: date
            )
            byID[record.id] = tombstone
            pendingRecordIDs.insert(record.id)
        }

        records = Array(byID.values).sortedByRecordName()
    }

    mutating func merge(_ remoteRecords: [BrowserSyncRecord]) throws {
        var byID = try validatedRecordDictionary()
        var incomingIDs: Set<BrowserSyncRecordID> = []

        guard remoteRecords.count <= Self.maximumRecordCount else {
            throw BrowserSyncError.recordLimitExceeded(remoteRecords.count)
        }

        for remote in remoteRecords {
            try remote.validate()
            guard incomingIDs.insert(remote.id).inserted else {
                throw BrowserSyncError.duplicateRecord(remote.id.recordName)
            }
            guard byID[remote.id] != nil || byID.count < Self.maximumRecordCount else {
                throw BrowserSyncError.recordLimitExceeded(byID.count + 1)
            }
            logicalClock = max(logicalClock, remote.version.logicalClock)

            guard let local = byID[remote.id] else {
                byID[remote.id] = remote
                continue
            }
            guard local.spaceID == remote.spaceID else {
                throw BrowserSyncError.crossSpaceConflict(remote.id.recordName)
            }

            let resolved = try BrowserSyncMergeResolver.resolve(local, remote)
            byID[remote.id] = resolved
            if resolved != remote {
                pendingRecordIDs.insert(resolved.id)
            }
        }

        records = Array(byID.values).sortedByRecordName()
    }

    mutating func prepareToOverwriteCloud(
        with session: BrowserSession,
        remoteRecords: [BrowserSyncRecord],
        at date: Date = .now
    ) throws {
        var recordsByID = try validatedRecordDictionary()
        var remoteIDs: Set<BrowserSyncRecordID> = []
        for remote in remoteRecords {
            try remote.validate()
            guard remoteIDs.insert(remote.id).inserted else {
                throw BrowserSyncError.duplicateRecord(remote.id.recordName)
            }
            recordsByID[remote.id] = remote
            logicalClock = max(logicalClock, remote.version.logicalClock)
        }

        let desiredPayloads = try BrowserSyncProjection.payloads(
            from: session,
            preferences: preferences,
            existingRecords: records
        )
        var desiredByID: [BrowserSyncRecordID: BrowserSyncPayload] = [:]
        for payload in desiredPayloads {
            guard desiredByID.updateValue(payload, forKey: payload.recordID) == nil else {
                throw BrowserSyncError.duplicateRecord(payload.recordID.recordName)
            }
        }
        let allIDs = Set(recordsByID.keys).union(desiredByID.keys)
        guard allIDs.count <= Self.maximumRecordCount else {
            throw BrowserSyncError.recordLimitExceeded(allIDs.count)
        }

        var overwritten: [BrowserSyncRecord] = []
        var pending: Set<BrowserSyncRecordID> = []
        for id in allIDs.sorted(by: { $0.recordName < $1.recordName }) {
            let record: BrowserSyncRecord
            if let payload = desiredByID[id] {
                record = .save(payload, version: try nextVersion())
            } else if let previous = recordsByID[id] {
                // "Replace iCloud with this device" answers which copy of the
                // synced categories wins. A category somebody turned off is not
                // projected at all, so tombstoning it here would erase content
                // this device was told to leave alone — cloud-wide. Keep the
                // record unchanged and unqueued, exactly as `stage` does.
                if let payload = previous.payload, !preferences.includes(payload) {
                    overwritten.append(previous)
                    continue
                }
                record = .delete(
                    id: id,
                    spaceID: previous.spaceID,
                    version: try nextVersion(),
                    reason: .superseded,
                    at: date
                )
            } else {
                throw BrowserSyncError.invalidRecord(id.recordName)
            }
            try record.validate()
            overwritten.append(record)
            pending.insert(record.id)
        }

        records = overwritten
        pendingRecordIDs = pending
    }

    mutating func replaceWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws {
        guard remoteRecords.count <= Self.maximumRecordCount else {
            throw BrowserSyncError.recordLimitExceeded(remoteRecords.count)
        }
        var remoteIDs: Set<BrowserSyncRecordID> = []
        var maximumClock = logicalClock
        for remote in remoteRecords {
            try remote.validate()
            guard remoteIDs.insert(remote.id).inserted else {
                throw BrowserSyncError.duplicateRecord(remote.id.recordName)
            }
            maximumClock = max(maximumClock, remote.version.logicalClock)
        }
        records = remoteRecords.sortedByRecordName()
        pendingRecordIDs = []
        logicalClock = maximumClock
    }

    mutating func markUploaded(_ recordIDs: Set<BrowserSyncRecordID>) {
        pendingRecordIDs.subtract(recordIDs)
    }

    mutating func markUploaded(_ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]) {
        let currentByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.version) })
        let exactlyAcknowledged = acknowledgedVersions.compactMap { id, version in
            currentByID[id] == version ? id : nil
        }
        pendingRecordIDs.subtract(exactlyAcknowledged)
    }

    func materializedSession(applyingTo localSession: BrowserSession) throws -> BrowserSession {
        try BrowserSyncMaterializer.materialize(
            records: BrowserSyncRecordReconciler.reconciledRecords(records),
            preferences: preferences,
            localSession: localSession
        )
    }

    private mutating func nextVersion() throws -> BrowserSyncVersion {
        guard logicalClock < UInt64.max else {
            throw BrowserSyncError.logicalClockExhausted
        }
        logicalClock += 1
        return BrowserSyncVersion(logicalClock: logicalClock, deviceID: deviceID)
    }

    /// Every Space the journal already has a record for, present or tombstoned.
    private static func spaceIDs(
        in recordsByID: [BrowserSyncRecordID: BrowserSyncRecord]
    ) -> Set<SpaceID> {
        Set(
            recordsByID.keys.compactMap { id in
                id.kind == .space ? SpaceID(rawValue: id.value) : nil
            }
        )
    }

    /// Every folder the journal already has a record for, present or tombstoned.
    private static func folderIDs(
        in recordsByID: [BrowserSyncRecordID: BrowserSyncRecord]
    ) -> Set<FolderID> {
        Set(
            recordsByID.keys.compactMap { id in
                id.kind == .folder ? FolderID(rawValue: id.value) : nil
            }
        )
    }

    /// The parent each folder that still has a payload names.
    ///
    /// A folder that is only a tombstone is deliberately absent, so an ancestry
    /// walk ends there. `updateValue` rather than a subscript assignment: writing
    /// `nil` through a subscript would remove a root folder's entry instead of
    /// recording that it has no parent.
    private static func parentIDsByFolderID(
        in recordsByID: [BrowserSyncRecordID: BrowserSyncRecord]
    ) -> [FolderID: FolderID?] {
        var result: [FolderID: FolderID?] = [:]
        for record in recordsByID.values {
            guard case .folder(let folder)? = record.payload else { continue }
            result.updateValue(folder.parentID, forKey: folder.id)
        }
        return result
    }

    /// Whether every folder above this payload is one the journal has heard of.
    ///
    /// Materialization holds a record out of the session while any folder above
    /// it has no record, exactly as it holds out a record whose Space has not
    /// arrived, so the same protection applies — and it has to reach the whole
    /// chain, because a tab's own folder can be present while that folder's
    /// parent is the one still missing. A folder somebody deleted keeps its
    /// tombstone, but its content is deliberately held until promoted payloads
    /// arrive because Crest's folder deletion removes only the container.
    private static func ancestryHasArrived(
        _ payload: BrowserSyncPayload,
        knownFolderIDs: Set<FolderID>,
        parentIDsByFolderID: [FolderID: FolderID?]
    ) -> Bool {
        var next: FolderID?
        switch payload {
        case .tab(let tab):
            next = tab.placement == .saved ? tab.folderID : nil
        case .folder(let folder):
            next = folder.parentID
        case .space, .history, .archive:
            next = nil
        }

        var seen: Set<FolderID> = []
        while let folderID = next {
            guard knownFolderIDs.contains(folderID) else { return false }
            // A cycle is never delivery order, so it is not this rule's to hold
            // back; materialization fails closed on it.
            guard seen.insert(folderID).inserted else { return true }
            // A folder with no payload is a tombstone. Deleting a folder in
            // Crest preserves its tabs and promotes its children, so the old
            // child records must wait for those moved payloads rather than be
            // cascaded into deletions above their remote versions.
            guard let parentID = parentIDsByFolderID[folderID] else { return false }
            next = parentID
        }
        return true
    }

    /// A live tab may leave sync only with evidence for why it left the session.
    /// Close and cleanup create an archive record; saved/pinned deletion creates
    /// a deletion audit; deleting a whole Space is the one parent-level action.
    /// Any other absence can be a stale window snapshot or partial Cloud batch,
    /// so keeping the record is safer than manufacturing a tombstone.
    private static func deletionReason(
        for payload: BrowserSyncPayload,
        desiredPayloadsByID: [BrowserSyncRecordID: BrowserSyncPayload],
        archivedTabReasonsByID: [TabID: TabArchiveReason],
        fallback: BrowserSyncTombstoneReason
    ) -> BrowserSyncTombstoneReason? {
        guard case .tab(let tab) = payload else {
            return switch payload {
            case .space, .folder:
                fallback == .explicitDelete ? .explicitDelete : nil
            case .history, .archive:
                fallback
            case .tab:
                nil
            }
        }
        if let archiveReason = archivedTabReasonsByID[tab.id] {
            if archiveReason.isExplicitDeletion { return .explicitDelete }
            if archiveReason == .autoCleanup { return .retention }
            return .superseded
        }
        let spaceRecordID = BrowserSyncRecordID(
            kind: .space,
            value: tab.spaceID.rawValue
        )
        if fallback == .explicitDelete,
            desiredPayloadsByID[spaceRecordID] == nil
        {
            return .explicitDelete
        }
        return nil
    }

    private func validatedRecordDictionary() throws -> [BrowserSyncRecordID: BrowserSyncRecord] {
        var result: [BrowserSyncRecordID: BrowserSyncRecord] = [:]
        for record in records {
            try record.validate()
            guard result.updateValue(record, forKey: record.id) == nil else {
                throw BrowserSyncError.duplicateRecord(record.id.recordName)
            }
        }
        return result
    }
}
