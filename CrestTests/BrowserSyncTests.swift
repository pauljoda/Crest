import Foundation
import XCTest

@testable import Crest

/// TRANSITIONAL until slice 8c ports the journal contract tests to the core: a
/// device whose file holds a session and its journal, opened as a launch opens
/// it, which takes cloud records through its core as the transport does.
@MainActor
final class BrowserSyncingDevice {
    // MARK: - Variables

    let harness: BrowserStoredSessionHarness

    /// The session the device's store shows.
    var session: BrowserSession { harness.store.session }

    /// The journal the device's core accepted last, as its file holds it.
    var journal: BrowserSyncJournal {
        do { return try harness.storedJournal() } catch {
            preconditionFailure("A session the core keeps in its file always has a journal there: \(error)")
        }
    }

    // MARK: - Initializers

    /// A device whose file holds `session` and `journal`.
    init(_ session: BrowserSession, journal: BrowserSyncJournal) throws {
        harness = try BrowserStoredSessionHarness(session: session, journal: journal)
    }

    /// A device whose file holds `session`, which its journal from `deviceID`
    /// staged at `date`.
    convenience init(_ session: BrowserSession, deviceID: UUID = UUID(), stagedAt date: Date) throws {
        var journal = BrowserSyncJournal(deviceID: deviceID)
        try journal.stage(session: session, at: date)
        try self.init(session, journal: journal)
    }

    // MARK: - Actions

    /// Merges `records` from the cloud, and answers the session the store
    /// shows then.
    @discardableResult
    func merge(_ records: [BrowserSyncRecord]) throws -> BrowserSession {
        try harness.deliverNow(MergeSyncRecords(records: records.map(SyncRecord.init(browser:))))
        return session
    }

    /// Replaces the session with what the cloud holds, and answers the
    /// session the store shows then.
    func replace(with records: [BrowserSyncRecord]) throws -> BrowserSession {
        try harness.deliverNow(ReplaceWithCloudRecords(records: records.map(SyncRecord.init(browser:))))
        return session
    }

    /// Rebases the journal above what the cloud holds.
    func overwrite(with records: [BrowserSyncRecord]) throws {
        try harness.deliverNow(OverwriteCloud(records: records.map(SyncRecord.init(browser:))))
    }

    /// Acknowledges `recordIDs` as uploaded, at the versions the journal
    /// holds them at.
    func markUploaded(_ recordIDs: Set<BrowserSyncRecordID>) throws {
        let uploaded = journal.records.filter { recordIDs.contains($0.id) }.map {
            UploadedRecord(
                record: SyncRecordReference(kind: SyncRecordKind(browser: $0.id.kind), id: $0.id.value),
                version: SyncVersion(clock: $0.version.logicalClock, deviceID: $0.version.deviceID))
        }
        try harness.deliverNow(AcknowledgeUploads(records: uploaded))
    }
}
