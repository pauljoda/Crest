#if CREST_CORE_BACKED
import Foundation
import XCTest
@testable import Crest

@MainActor
final class BrowserCoreSessionRecoveryTests: XCTestCase {
    func testRecoveryPreservesFailedFilesAndRestoresSessionAndJournalBeforeLaunching() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.sqlite")
        let original = BrowserSession.preview
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try makeCheckpoint(url, session: original, journal: journal)
        let broken = Data("unreadable original".utf8)
        try broken.write(to: url)
        let sidecar = URL(fileURLWithPath: url.path + "-wal")
        let sidecarBytes = Data("preserve unreadable WAL".utf8)
        try sidecarBytes.write(to: sidecar)
        var successfulLaunches = 0
        let launch = BrowserApplicationLaunch {
            do {
                let storage = try BrowserTransactionalSessionPersistence(url: url, favicons: InMemoryBrowserFaviconStore())
                successfulLaunches += 1
                return storage
            } catch { throw BrowserSessionStartupFailure(storeURL: url, underlying: error) }
        }
        XCTAssertNil(launch.value)
        XCTAssertEqual(successfulLaunches, 0)
        XCTAssertNotNil(launch.failure?.checkpointDate)
        launch.restore()
        let restored = try XCTUnwrap(launch.value)
        XCTAssertEqual(restored.load(), original)
        let restoredJournal = try XCTUnwrap(restored.journalPersistence.load())
        XCTAssertNotEqual(restoredJournal.deviceID, journal.deviceID)
        XCTAssertEqual(restoredJournal.records, journal.records)
        XCTAssertEqual(restoredJournal.logicalClock, journal.logicalClock)
        XCTAssertEqual(restoredJournal.pendingRecordIDs, journal.pendingRecordIDs)
        let saved = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("Recovery-") })
        XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("session.sqlite")), broken)
        XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("session.sqlite-wal")), sidecarBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: BrowserSessionRecovery.cloudMarker(for: url).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: BrowserSessionRecovery.restoreMarker(for: url).path))
        launch.retry()
        XCTAssertEqual(successfulLaunches, 1)
    }

    func testInvalidBackupDoesNotReplaceOriginalAndFutureVersionCannotOfferRollback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("session.sqlite")
        let original = Data("original bytes".utf8)
        try original.write(to: url)
        try Data("invalid backup".utf8).write(to: BrowserSessionRecovery.checkpointURL(for: url))
        XCTAssertThrowsError(try BrowserSessionRecovery.restore(url))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: BrowserSessionRecovery.restoreMarker(for: url).path))
        let failure = BrowserSessionStartupFailure(storeURL: url,
            underlying: BrowserTransactionalSessionPersistence.StorageError.unsupportedVersion)
        XCTAssertTrue(failure.requiresNewerApp)
        XCTAssertNil(failure.checkpointDate)
        XCTAssertThrowsError(try failure.restore())
    }

    func testInterruptedRestoreCannotSeedAnEmptySessionAndCanResume() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.sqlite")
        let original = BrowserSession.preview
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try makeCheckpoint(url, session: original, journal: journal)
        try FileManager.default.removeItem(at: url)
        try Data().write(to: BrowserSessionRecovery.restoreMarker(for: url))
        XCTAssertThrowsError(try BrowserTransactionalSessionPersistence(url: url, favicons: InMemoryBrowserFaviconStore())) {
            guard case BrowserTransactionalSessionPersistence.StorageError.interruptedRestore = $0 else {
                return XCTFail("Expected interrupted restore, got \($0)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try BrowserSessionRecovery.restore(url)
        let restored = try BrowserTransactionalSessionPersistence(url: url, favicons: InMemoryBrowserFaviconStore())
        XCTAssertEqual(restored.load(), original)
    }

    func testRestoredJournalRequiresFullCloudMergeAndRetainsAccountConfirmation() throws {
        let persistence = CloudState()
        persistence.state.reconciliationReason = .accountChange
        try BrowserSessionRecovery.resetCloudCursor(persistence)
        XCTAssertTrue(persistence.state.requiresFullPull)
        XCTAssertTrue(persistence.state.requiresAccountConfirmation)
        XCTAssertNil(persistence.state.engineStateSerialization)
        XCTAssertNil(persistence.state.conflictResolution)
    }

    private func makeCheckpoint(_ url: URL, session: BrowserSession, journal: BrowserSyncJournal) throws {
        let storage = try BrowserTransactionalSessionPersistence(url: url, favicons: InMemoryBrowserFaviconStore())
        try storage.migrateIfNeeded(session: session, journal: journal)
        try storage.saveRecoveryCheckpoint()
    }

    private final class CloudState: BrowserCloudSyncStatePersisting, @unchecked Sendable {
        var state = BrowserCloudSyncState()
        func load() throws -> BrowserCloudSyncState? { state }
        func save(_ state: BrowserCloudSyncState) throws { self.state = state }
        func reset() throws { state = BrowserCloudSyncState() }
    }
}
#endif
