#if CREST_CORE_BACKED
import Foundation
import XCTest
@testable import Crest

@MainActor
final class BrowserCoreSessionAuthorityTests: XCTestCase {
    func testDeletionIntentSurvivesAdapterFailureAndRestartThenCommitsItsTombstoneWithTheSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.sqlite")
        let icons = InMemoryBrowserFaviconStore()
        let storage = try BrowserTransactionalSessionPersistence(url: url, favicons: icons)
        let original = BrowserSession.preview
        let target = original.spaces[0]
        var initialJournal = BrowserSyncJournal()
        try initialJournal.stage(session: original)
        try storage.migrateIfNeeded(session: original, journal: initialJournal)
        let sync = BrowserSyncCoordinator(persistence: storage.journalPersistence)
        let store = BrowserStore(session: original, persistence: storage, syncCoordinator: sync)
        let other = store.makeWindowStore()
        let failing = DeletionAdapter { space in
            let intent = try XCTUnwrap(storage.load()?.spaceDeletions?.first)
            XCTAssertEqual(intent.spaceID, space.id)
            XCTAssertEqual(intent.profileID, space.profile.id)
            XCTAssertTrue(other.deletingSpaceIDs.contains(space.id))
            XCTAssertNotEqual(other.selectedSpace?.id, space.id)
            throw DeletionFailure.interrupted
        }
        do { try await store.deleteSpace(target.id, dataDeleter: failing); XCTFail("Expected adapter failure") }
        catch DeletionFailure.interrupted { }
        XCTAssertTrue(store.deletingSpaceIDs.contains(target.id))
        let saved = try XCTUnwrap(storage.load())
        XCTAssertNotNil(saved.space(id: target.id))
        var staleWindow = saved
        staleWindow.selectedSpaceID = target.id
        let pages = BrowserPagePool()
        pages.select(session: staleWindow)
        XCTAssertNil(pages.activePage, "A restored window must not reopen a pending profile")
        let reopened = try BrowserTransactionalSessionPersistence(url: url, favicons: icons)
        let restartedSync = BrowserSyncCoordinator(persistence: reopened.journalPersistence)
        let restarted = BrowserStore(session: saved, persistence: reopened, syncCoordinator: restartedSync)
        XCTAssertTrue(restarted.deletingSpaceIDs.contains(target.id))
        XCTAssertNotEqual(restarted.selectedSpace?.id, target.id)
        let succeeding = DeletionAdapter { space in XCTAssertEqual(space.profile.id, target.profile.id) }
        await restarted.resumePendingSpaceDeletions(dataDeleter: succeeding)
        XCTAssertEqual(succeeding.calls, [target.id])
        XCTAssertNil(restarted.session.space(id: target.id))
        XCTAssertNil(restarted.session.spaceDeletions)
        XCTAssertEqual(reopened.load(), restarted.session)
        XCTAssertEqual(try reopened.journalPersistence.load(), restartedSync.journal)
        let tombstones = restartedSync.journal.records.filter { $0.spaceID == target.id && $0.tombstone != nil }
        XCTAssertFalse(tombstones.isEmpty)
        XCTAssertTrue(tombstones.allSatisfy { $0.tombstone?.reason == .explicitDelete })
    }

    func testRemoteSpaceDeletionDurablySchedulesTheRegisteredAdapterAndRetriesFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try BrowserTransactionalSessionPersistence(url: directory.appendingPathComponent("session.sqlite"), favicons: InMemoryBrowserFaviconStore())
        let original = BrowserSession.preview
        let target = original.spaces[0]
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try storage.migrateIfNeeded(session: original, journal: journal)
        let sync = BrowserSyncCoordinator(persistence: storage.journalPersistence)
        let store = BrowserStore(session: original, persistence: storage, syncCoordinator: sync)
        let other = store.makeWindowStore()
        var fail = true
        let adapter = DeletionAdapter { space in
            XCTAssertEqual(space.profile.id, target.profile.id)
            XCTAssertEqual(storage.load()?.spaceDeletions?.first?.spaceID, target.id)
            XCTAssertTrue(try XCTUnwrap(storage.journalPersistence.load()).records.contains { $0.spaceID == target.id && $0.id.kind == .space && $0.tombstone?.reason == .explicitDelete })
            XCTAssertTrue(other.deletingSpaceIDs.contains(target.id))
            XCTAssertNotEqual(other.selectedSpace?.id, target.id)
            if fail { throw DeletionFailure.interrupted }
        }
        store.family.configureSpaceDataCleanup(adapter, from: store)
        var remote = original
        remote.spaces.removeAll { $0.id == target.id }
        remote.selectedSpaceID = remote.spaces[0].id
        var incoming = journal
        try incoming.stage(session: remote, deletionReason: .explicitDelete)
        try store.mergeRemoteSyncRecords(incoming.records)
        XCTAssertTrue(adapter.calls.isEmpty, "Cleanup must be scheduled after the durable sync commit")
        await store.family.spaceCleanupTask?.value
        XCTAssertEqual(adapter.calls, [target.id])
        XCTAssertNotNil(storage.load()?.spaceDeletions?.first)
        fail = false
        try store.mergeRemoteSyncRecords(incoming.records)
        await store.family.spaceCleanupTask?.value
        XCTAssertEqual(adapter.calls, [target.id, target.id])
        XCTAssertNil(store.session.space(id: target.id))
        XCTAssertNil(store.session.spaceDeletions)
        XCTAssertEqual(storage.load(), store.session)
        XCTAssertEqual(try storage.journalPersistence.load(), sync.journal)
        XCTAssertEqual(other.session.spaces.map(\.id), store.session.spaces.map(\.id))
    }

    private enum DeletionFailure: Error { case interrupted }
    private final class DeletionAdapter: BrowserSpaceDataDeleting {
        var calls: [SpaceID] = []
        let action: (BrowserSpace) throws -> Void
        init(action: @escaping (BrowserSpace) throws -> Void) { self.action = action }
        func deleteData(for space: BrowserSpace) async throws { calls.append(space.id); try action(space) }
    }

    func testTransactionalStorageRollsBackBothPartsAndRecoversTheCommittedPair() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.sqlite")
        let icons = InMemoryBrowserFaviconStore()
        let storage = try BrowserTransactionalSessionPersistence(url: url, favicons: icons)
        var original = BrowserSession.preview
        original.recordVisit(url: URL(string: "https://example.org/before")!, title: "Before")
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try storage.migrateIfNeeded(session: original, journal: journal)
        let core = BrowserCoreSessionAuthority(session: original)
        var next = original
        next.spaces[0].name = "After transaction"
        next.recordVisit(url: URL(string: "https://example.org/after")!, title: "After")
        var nextJournal = journal
        try nextJournal.stage(session: next)
        XCTAssertThrowsError(try core.replaceDurably(with: next) { checkpoint in
            try storage.commit(next, checkpoint: MissingHistoryCheckpoint(core: try XCTUnwrap(checkpoint.coreData())), journal: nextJournal)
        })
        XCTAssertEqual(core.projection, original)
        let afterFailure = try BrowserTransactionalSessionPersistence(url: url, favicons: icons)
        XCTAssertEqual(afterFailure.load(), original)
        XCTAssertEqual(try afterFailure.journalPersistence.load(), journal)

        try core.replaceDurably(with: next) { checkpoint in
            try storage.commit(next, checkpoint: checkpoint, journal: nextJournal)
        }
        let reopened = try BrowserTransactionalSessionPersistence(url: url, favicons: icons)
        XCTAssertEqual(reopened.load(), next)
        XCTAssertEqual(try reopened.journalPersistence.load(), nextJournal)
        // A later launch must never overwrite accepted data with a legacy copy.
        try reopened.migrateIfNeeded(session: original, journal: journal)
        XCTAssertEqual(reopened.load(), next)
    }

    func testIncomingSyncPublishesAndPersistsTheSameSessionAcrossWindows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let icons = InMemoryBrowserFaviconStore()
        let storage = try BrowserTransactionalSessionPersistence(url: directory.appendingPathComponent("session.sqlite"), favicons: icons)
        let original = BrowserSession.preview
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try storage.migrateIfNeeded(session: original, journal: journal)
        let coordinator = BrowserSyncCoordinator(persistence: storage.journalPersistence)
        let store = BrowserStore(session: original, persistence: storage, syncCoordinator: coordinator)
        let other = store.makeWindowStore()
        var remote = original
        remote.spaces[0].name = "Remote Space"
        var remoteJournal = journal
        try remoteJournal.stage(session: remote)
        try store.mergeRemoteSyncRecords(remoteJournal.records)
        XCTAssertEqual(store.session.spaces[0].name, "Remote Space")
        XCTAssertEqual(other.session.spaces[0].name, "Remote Space")
        XCTAssertEqual(storage.load(), store.session)
        XCTAssertEqual(try storage.journalPersistence.load(), coordinator.journal)
        // A local save may precede its coalesced projection. On restart, staging
        // that durable session restores the pending edit without losing history.
        store.updateSpaceIdentity(original.spaces[0].id, name: "Local after sync", symbol: "book", accent: .teal)
        await store.flushPendingSyncPersistence()
        let restored = try XCTUnwrap(storage.load())
        XCTAssertEqual(restored.spaces[0].name, "Local after sync")
        XCTAssertEqual(try storage.journalPersistence.load(), coordinator.journal)
    }

    private final class MissingHistoryCheckpoint: BrowserSessionCheckpoint {
        let core: Data
        init(core: Data) { self.core = core }
        func coreData() -> Data? { core }
        func historyData(in spaceID: SpaceID) -> Data? { nil }
    }

    func testCoreRepairPreservesAssetOwnershipWhenIdentitiesCollide() throws {
        var first = BrowserSession.preview.spaces[0]
        first.tabs = [first.tabs[0]]
        first.tabs[0].faviconData = Data([1])
        var second = first
        second.tabs[0].faviconData = Data([2])
        let original = BrowserSession(spaces: [first, second], selectedSpaceID: first.id)
        let repaired = try BrowserCoreSync.repair(original)
        XCTAssertNotEqual(repaired.spaces[0].id, repaired.spaces[1].id)
        XCTAssertNotEqual(repaired.spaces[0].profile.id, repaired.spaces[1].profile.id)
        XCTAssertNotEqual(repaired.spaces[0].tabs[0].id, repaired.spaces[1].tabs[0].id)
        XCTAssertEqual(repaired.spaces[0].tabs[0].faviconData, Data([1]))
        XCTAssertEqual(repaired.spaces[1].tabs[0].faviconData, Data([2]))
        XCTAssertEqual(original.spaces[0].id, original.spaces[1].id)
    }

    func testSpaceCommandsPreserveNativeRecordsAndPublishAcrossWindows() throws {
        var session = BrowserSession.preview
        let icon = Data([3, 2, 1])
        session.spaces[0].tabs[0].faviconData = icon
        let store = BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
        let other = store.makeWindowStore(restoresTabSelection: false)
        let id = session.spaces[0].id
        store.updateSpaceIdentity(id, name: "  Research  ", symbol: " ", accent: .teal)
        XCTAssertEqual(other.session.space(id: id)?.name, "Research")
        XCTAssertEqual(other.session.space(id: id)?.tabs[0].faviconData, icon)
        XCTAssertNil(other.session.space(id: id)?.selectedTabID)
        store.setDefaultSpace(id)
        store.addSpace()
        XCTAssertEqual(store.session.spaces.count, session.spaces.count + 1)
        XCTAssertEqual(other.session.spaces.count, store.session.spaces.count)
        XCTAssertEqual(other.session.selectedSpaceID, id)
        XCTAssertEqual(store.session.defaultSpaceID, id)
        XCTAssertEqual(store.session.spaces.last?.name, "Space 3")
        let folderID = try XCTUnwrap(store.addFolder(title: "Research", color: .teal, in: id))
        XCTAssertEqual(other.session.space(id: id)?.folders.first { $0.id == folderID }?.color, .teal)
        XCTAssertTrue(store.setFolderSymbol(folderID, in: id, symbol: "book"))
        XCTAssertTrue(store.setFolderColor(folderID, in: id, color: .gold))
        XCTAssertEqual(other.session.space(id: id)?.folders.first { $0.id == folderID }?.symbol, "book")
        XCTAssertEqual(other.session.space(id: id)?.folders.first { $0.id == folderID }?.color, .gold)
        XCTAssertNil(store.localSyncErrorDescription)
    }

    func testDirectCommandsKeepWindowSelectionAssetsAndSavedProjectionConsistent() throws {
        var original = BrowserSession.preview
        let spaceID = original.spaces[0].id
        let tabID = original.spaces[0].tabs[0].id
        let icon = Data([1, 2, 3])
        original.spaces[0].tabs[0].faviconData = icon
        original.recordVisit(url: URL(string: "https://example.org/direct")!, title: "Visit")
        let core = BrowserCoreSessionAuthority(session: original)
        var window = original
        window.selectedSpaceID = original.spaces[1].id
        window.spaces[0].selectedTabID = nil
        _ = try core.execute("tab.rename", in: spaceID,
            arguments: ["tabId": tabID.rawValue.uuidString, "title": "Core command"], window: window, at: .now)
        XCTAssertEqual(core.projection.selectedSpaceID, window.selectedSpaceID)
        XCTAssertNil(core.projection.spaces[0].selectedTabID)
        XCTAssertEqual(core.projection.spaces[0].tabs[0].faviconData, icon)
        XCTAssertEqual(core.projection.spaces[0].history, original.spaces[0].history)
        let checkpoint = try core.checkpoint(for: core.projection)
        let restored = try JSONDecoder().decode(BrowserSession.self, from: XCTUnwrap(checkpoint.coreData()))
        XCTAssertEqual(restored.selectedSpaceID, core.projection.selectedSpaceID)
        XCTAssertNil(restored.spaces[0].selectedTabID)
        XCTAssertEqual(restored.spaces[0].tabs[0].customTitle, "Core command")
    }

    func testCoreCheckpointPersistsTheCapturedRevisionAndEmptyWindowSelection() async throws {
        let suite = "crest.core-authority-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let icons = InMemoryBrowserFaviconStore()
        let persistence = UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: icons)
        var original = BrowserSession.preview
        original.recordVisit(url: URL(string: "https://example.org/checkpoint")!, title: "Checkpoint")
        let core = BrowserCoreSessionAuthority(session: original)
        var emptyWindow = original
        emptyWindow.spaces[0].selectedTabID = nil
        let checkpoint = try core.checkpoint(for: emptyWindow)
        var next = original
        next.spaces[0].tabs[0].customTitle = "Edited after snapshot"
        next.spaces[0].history = []
        next.spaces.removeLast()
        try core.replace(with: next)
        persistence.save(emptyWindow, scope: .everything, checkpoint: checkpoint)
        await persistence.flushPendingSaves()
        let restored = UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: icons).load()
        XCTAssertEqual(restored, emptyWindow)
        XCTAssertEqual(core.projection, next)
    }
}
#endif
