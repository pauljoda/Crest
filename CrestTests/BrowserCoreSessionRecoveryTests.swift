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

    /// The upgrade every installed reader performs: the shipped release's
    /// `UserDefaults` session, its per-Space history keys, its favicon files and
    /// its sync journal have to arrive in the core checkpoint intact, exactly
    /// once, with the installed values retained for a rollback to that release.
    func testUpgradingTheInstalledDefaultsSessionPreservesEveryRecordAndMigratesOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "com.pauldavis.crest.tests.upgrade." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let favicons = BrowserFaviconFileStore(
            rootDirectory: directory.appendingPathComponent("Favicons", isDirectory: true))
        let journalStore = UserDefaultsBrowserSyncJournalPersistence(defaults: defaults)

        // Write the installed release's own stores, through its own types.
        let installed = try makeInstalledSession()
        let writer = UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: favicons)
        writer.save(installed, scope: .everything)
        await writer.flushPendingSaves()
        // A journal the installed release had uploaded once, then a Space the
        // reader deleted whose tombstone and pending uploads are still owed.
        var journal = BrowserSyncJournal()
        var beforeDeletion = installed
        beforeDeletion.spaces.append(BrowserSession.makeBlankSpace(number: 9))
        try journal.stage(session: beforeDeletion)
        try journal.markUploaded(Set(journal.records.map(\.id)))
        XCTAssertTrue(journal.pendingRecordIDs.isEmpty)
        try journal.stage(session: installed, deletionReason: .explicitDelete)
        try journalStore.save(journal)
        XCTAssertTrue(journal.records.contains { $0.tombstone?.reason == .explicitDelete })
        XCTAssertFalse(journal.pendingRecordIDs.isEmpty)
        // Per-window selection is a separate record in the same domain. The
        // upgrade must read it in place rather than carry or clear it.
        let windowStates = UserDefaultsBrowserWindowStatePersistence(defaults: defaults)
        let windowState = BrowserWindowState(selectedSpaceID: installed.spaces[1].id,
            selectedTabIDsBySpace: Dictionary(uniqueKeysWithValues: installed.spaces.compactMap { space in
                space.selectedTabID.map { (space.id, $0) }
            }))
        windowStates.save(windowState)
        await windowStates.flushPendingSaves()

        // A launch reads those stores fresh, exactly as the upgraded app does.
        let storage = try BrowserStore.migratedStorage(directory: directory,
            legacy: UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: favicons),
            journal: journalStore, favicons: favicons, environment: .current)
        let migrated = try XCTUnwrap(storage.load())
        XCTAssertEqual(migrated, installed)
        // Spelled out, because each of these is a separate way to "start over".
        XCTAssertEqual(migrated.spaces.map(\.id), installed.spaces.map(\.id))
        // Website data, credentials and the tab-state archive are all keyed by
        // the profile identity, so a new one would orphan every one of them.
        XCTAssertEqual(migrated.spaces.map(\.profile.id), installed.spaces.map(\.profile.id))
        XCTAssertEqual(migrated.defaultSpaceID, installed.defaultSpaceID)
        XCTAssertEqual(migrated.spaces.map(\.accessPolicy), installed.spaces.map(\.accessPolicy))
        XCTAssertTrue(migrated.spaces.contains { $0.accessPolicy != .open })
        XCTAssertEqual(migrated.spaces.map { $0.tabs.map(\.id) }, installed.spaces.map { $0.tabs.map(\.id) })
        XCTAssertEqual(migrated.spaces.map { $0.folders.map(\.id) }, installed.spaces.map { $0.folders.map(\.id) })
        XCTAssertEqual(migrated.spaces.map(\.splitGroups), installed.spaces.map(\.splitGroups))
        XCTAssertEqual(migrated.spaces.map { $0.tabs.map(\.splitGroupID) },
            installed.spaces.map { $0.tabs.map(\.splitGroupID) })
        XCTAssertEqual(migrated.spaces.map(\.archivedTabs), installed.spaces.map(\.archivedTabs))
        XCTAssertEqual(migrated.spaces.map(\.history), installed.spaces.map(\.history))
        XCTAssertFalse(migrated.spaces.flatMap(\.splitGroups).isEmpty)
        XCTAssertFalse(migrated.spaces.flatMap { $0.tabs.compactMap(\.splitGroupID) }.isEmpty)
        XCTAssertFalse(migrated.spaces.flatMap(\.archivedTabs).isEmpty)
        XCTAssertFalse(migrated.spaces.flatMap(\.folders).isEmpty)
        XCTAssertFalse(migrated.spaces.flatMap(\.history).isEmpty)
        XCTAssertTrue(migrated.spaces.allSatisfy { $0.tabs.contains { $0.faviconData != nil } })

        // The journal keeps its device identity, clock, records and the uploads
        // the installed release had not acknowledged yet.
        let migratedJournal = try XCTUnwrap(try storage.journalPersistence.load())
        XCTAssertEqual(migratedJournal.deviceID, journal.deviceID)
        XCTAssertEqual(migratedJournal.logicalClock, journal.logicalClock)
        XCTAssertEqual(migratedJournal.records, journal.records)
        XCTAssertEqual(migratedJournal.pendingRecordIDs, journal.pendingRecordIDs)
        XCTAssertTrue(migratedJournal.records.contains { $0.tombstone != nil })

        // A recovery copy exists before the app may write anything else.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: BrowserSessionRecovery.checkpointURL(for: storage.url).path))
        // The installed release's values stay readable for a rollback.
        XCTAssertNotNil(defaults.data(forKey: UserDefaultsBrowserSessionPersistence.coreKey))
        XCTAssertNotNil(defaults.data(
            forKey: UserDefaultsBrowserSessionPersistence.historyKey(for: installed.spaces[0].id)))
        XCTAssertEqual(windowStates.load(id: windowState.id), windowState)

        // A second launch must keep the accepted checkpoint even when the
        // retained legacy copy has since changed.
        defaults.set(try JSONEncoder().encode(BrowserSession.freshInstallSeed),
            forKey: UserDefaultsBrowserSessionPersistence.coreKey)
        let relaunched = try BrowserStore.migratedStorage(directory: directory,
            legacy: UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: favicons),
            journal: journalStore, favicons: favicons, environment: .current)
        XCTAssertEqual(relaunched.load(), installed)
        XCTAssertEqual(try relaunched.journalPersistence.load()?.records, journal.records)
    }

    /// An upgrade that finds a core the installed release could not decode. Its
    /// bytes have to survive, the app still has to launch, and the empty seed
    /// that stands in must never be published as a deletion of the real Spaces.
    func testUpgradingAnUnreadableInstalledCoreLaunchesAndAsksForAFullCloudPull() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "com.pauldavis.crest.tests.upgrade." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let favicons = BrowserFaviconFileStore(
            rootDirectory: directory.appendingPathComponent("Favicons", isDirectory: true))
        let unreadable = Data("a core a later build may still read".utf8)
        defaults.set(unreadable, forKey: UserDefaultsBrowserSessionPersistence.coreKey)

        let legacy = UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: favicons)
        let storage = try BrowserStore.migratedStorage(directory: directory, legacy: legacy,
            journal: UserDefaultsBrowserSyncJournalPersistence(defaults: defaults),
            favicons: favicons, environment: .current)
        // Nothing was carried, so launch seeds a disposable fresh install rather
        // than committing an empty session over the reader's own Space IDs.
        XCTAssertNil(storage.load())
        XCTAssertEqual(legacy.preservedUnreadableSessionData(), unreadable)
        XCTAssertEqual(defaults.data(forKey: UserDefaultsBrowserSessionPersistence.coreKey), unreadable)
        // The cloud-recovery request stays on disk until a transport consumes it
        // and resets the cursor, so the seed is replaced by a full pull.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: BrowserSessionRecovery.cloudMarker(for: storage.url).path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: BrowserSessionRecovery.checkpointURL(for: storage.url).path))
    }

    /// Spaces with distinct profiles, folders, pinned/saved/current tabs, a
    /// split, an archive, per-Space history, favicon bytes and a locked Space.
    private func makeInstalledSession() throws -> BrowserSession {
        var session = BrowserSession.showcase
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertGreaterThan(session.spaces.count, 1)
        XCTAssertFalse(session.spaces.flatMap { $0.tabs.compactMap(\.splitGroupID) }.isEmpty)
        XCTAssertFalse(session.spaces.flatMap(\.archivedTabs).isEmpty)
        XCTAssertFalse(session.spaces.flatMap(\.folders).isEmpty)
        for index in session.spaces.indices {
            // A split the reader has named, which is stored apart from the
            // membership the tabs carry.
            if let group = session.spaces[index].tabs.compactMap(\.splitGroupID).first {
                session.spaces[index].splitGroups = [BrowserSplitGroupMetadata(id: group,
                    customTitle: "Research", titleModifiedAt: epoch)]
            }
            for tab in session.spaces[index].tabs.indices {
                session.spaces[index].tabs[tab].faviconData = Data(
                    repeating: UInt8(truncatingIfNeeded: index * 17 + tab), count: 512)
            }
            session.spaces[index].history = (0..<12).map { entry in
                BrowserHistoryEntry(
                    url: URL(string: "https://example.com/space-\(index)/page-\(entry)")!,
                    title: "Space \(index) page \(entry)",
                    firstVisitedAt: epoch,
                    lastVisitedAt: epoch.addingTimeInterval(Double(entry)),
                    visitCount: entry % 5 + 1)
            }
        }
        session.spaces[1].accessPolicy = .deviceOwnerAuthentication
        session.defaultSpaceID = session.spaces[0].id
        XCTAssertEqual(Set(session.spaces.map(\.profile.id)).count, session.spaces.count)
        return session
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
