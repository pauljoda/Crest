import Foundation
import XCTest
@testable import Crest

@MainActor
final class BrowserCoreSessionAuthorityTests: XCTestCase {
    func testBatchDeletionCommitsExplicitTombstonesWithSavedTabRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try BrowserTransactionalSessionPersistence(
            url: directory.appendingPathComponent("session.sqlite"), favicons: InMemoryBrowserFaviconStore())
        var original = BrowserSession.preview
        let tabs = Array(original.spaces[0].tabs.filter { $0.url != nil && !$0.isStartPage }.prefix(2))
        XCTAssertEqual(tabs.count, 2)
        let ids = Set(tabs.map(\.id))
        for index in original.spaces[0].tabs.indices where ids.contains(original.spaces[0].tabs[index].id) {
            original.spaces[0].tabs[index].placement = .saved
            original.spaces[0].tabs[index].folderID = nil
            original.spaces[0].tabs[index].splitGroupID = nil
        }
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try storage.migrateIfNeeded(session: original, journal: journal)
        let sync = BrowserSyncCoordinator(persistence: storage.journalPersistence)
        let store = BrowserStore(session: original, selection: showing(original.spaces[0]), persistence: storage,
            syncCoordinator: sync)
        let request = BrowserTabBatchRequest(ids: tabs.map(\.id), in: original.spaces[0])
        try store.commitTabBatch(request, action: .delete)
        let saved = try XCTUnwrap(storage.load())
        XCTAssertTrue(saved.spaces[0].tabs.allSatisfy { !ids.contains($0.id) })
        XCTAssertEqual(saved, store.session)
        let committed = try XCTUnwrap(storage.journalPersistence.load())
        XCTAssertEqual(committed, sync.journal)
        for tab in tabs {
            let record = try XCTUnwrap(committed.records.first {
                $0.id == BrowserSyncRecordID(kind: .tab, value: tab.id.rawValue)
            })
            XCTAssertEqual(record.tombstone?.reason, .explicitDelete)
        }
    }

    func testRecordCommandsPreserveNativeAssetsAndOtherWindowSelection() throws {
        var original = BrowserSession.preview
        let spaceID = original.spaces[0].id
        original.spaces[0].history = []
        var archived = BrowserTab(title: "Archived", url: URL(string: "https://example.org/archive"), placement: .current)
        archived.faviconData = Data([1, 3, 5])
        original.spaces[0].archivedTabs = [ArchivedTab(tab: archived, archivedAt: .now, reason: .closed)]
        let store = BrowserStore(session: original, selection: showing(original.spaces[0]),
            persistence: InMemoryBrowserSessionPersistence())
        let other = store.makeWindowStore()
        other.selectSpace(original.spaces[1].id)
        let otherSpace = other.selectedSpace?.id
        let otherTab = other.selectedTab?.id

        store.recordVisit(url: try XCTUnwrap(URL(string: "https://example.org/visit#one")), title: "First")
        let visit = try XCTUnwrap(store.selectedSpace?.history.first)
        store.recordVisit(url: try XCTUnwrap(URL(string: "https://example.org/visit#two")), title: "Second")
        XCTAssertEqual(store.selectedSpace?.history.first?.id, visit.id)
        XCTAssertEqual(store.selectedSpace?.history.first?.visitCount, 2)
        XCTAssertEqual(other.session.space(id: spaceID)?.history, store.selectedSpace?.history)

        store.restoreArchivedTab(archived.id)
        XCTAssertEqual(store.selectedTab?.id, archived.id)
        XCTAssertEqual(store.selectedTab?.faviconData, archived.faviconData)
        XCTAssertTrue(try XCTUnwrap(other.session.space(id: spaceID)).archivedTabs.isEmpty)
        XCTAssertEqual(other.selectedSpace?.id, otherSpace)
        XCTAssertEqual(other.selectedTab?.id, otherTab)

        store.selectTab(original.spaces[0].tabs[0].id)
        store.sweepExpiredBrowsingData(now: .now.addingTimeInterval(86400 * 2))
        XCTAssertEqual(store.session.space(id: spaceID)?.archivedTabs.first(where: { $0.id == archived.id })?.tab.faviconData,
            archived.faviconData)
        XCTAssertNil(store.localSyncErrorDescription)
    }

    func testFailedTransferStorageReleasesBothWritersWhileThePreparedValueIsStillAlive() throws {
        enum Failure: Error { case disk }
        let original = BrowserSession.preview
        let assignment = BrowserSpaceRuntimeAssignment(space: original.spaces[0])
        let tab = original.spaces[0].tabs[0]
        let a = BrowserCoreSessionAuthority(session: original)
        let b = try a.makeBorrowed(in: assignment)
        let empty = b.projection
        let sourceView = BrowserStoreSelection(launching: original)
        var destinationView = BrowserStoreSelection(launching: empty)
        let command = try BrowserCoreSessionAuthority.prepareTransfer(source: a, sourceView: sourceView,
            destination: b, destinationView: destinationView, tabID: tab.id, assignment: assignment, fallback: nil,
            selecting: true)
        XCTAssertThrowsError(try BrowserCoreSessionAuthority.commitTransfer(command, source: a, destination: b) { _, _ in
            throw Failure.disk
        })
        XCTAssertEqual(a.projection, original)
        XCTAssertEqual(b.projection, empty)
        let retry = try BrowserCoreSessionAuthority.prepareTransfer(source: a, sourceView: sourceView,
            destination: b, destinationView: destinationView, tabID: tab.id, assignment: assignment, fallback: nil,
            selecting: true)
        try BrowserCoreSessionAuthority.commitTransfer(retry, source: a, destination: b) { _, _ in }
        XCTAssertFalse(a.projection.tabIDs.contains(tab.id))
        destinationView.apply(retry.destinationHint)
        XCTAssertEqual(destinationView.selectedTabID(in: assignment.spaceID), tab.id)
    }

    func testWorkspaceTransferSavesThePersistentOwnerAndJournalTogetherBeforeReconcilingWindows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try BrowserTransactionalSessionPersistence(url: directory.appendingPathComponent("session.sqlite"),
            favicons: InMemoryBrowserFaviconStore())
        var original = BrowserSession.preview
        let spaceID = original.spaces[0].id
        let tabID = original.spaces[0].tabs[0].id
        original.spaces[0].tabs[0].faviconData = Data([5, 8, 13])
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try storage.migrateIfNeeded(session: original, journal: journal)
        let sync = BrowserSyncCoordinator(persistence: storage.journalPersistence)
        let source = BrowserStore(session: original, persistence: storage, syncCoordinator: sync)
        let observer = source.makeWindowStore()
        let assignment = BrowserSpaceRuntimeAssignment(space: original.spaces[0])
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        XCTAssertTrue(source.transferTab(tabID, matching: assignment, to: temporary, in: assignment))
        XCTAssertFalse(observer.session.tabIDs.contains(tabID))
        XCTAssertEqual(storage.load(), source.session)
        XCTAssertEqual(try storage.journalPersistence.load(), sync.journal)
        XCTAssertEqual(temporary.selectedTab?.faviconData, Data([5, 8, 13]))
        XCTAssertFalse(source.session.space(id: spaceID)!.archivedTabs.contains { $0.id == tabID })
        XCTAssertTrue(temporary.transferTab(tabID, matching: assignment, to: source, in: assignment))
        XCTAssertEqual(source.selectedTab?.id, tabID)
        XCTAssertTrue(observer.session.tabIDs.contains(tabID))
        XCTAssertEqual(storage.load(), source.session)
        XCTAssertEqual(try storage.journalPersistence.load(), sync.journal)
        XCTAssertEqual(source.selectedTab?.faviconData, Data([5, 8, 13]))
    }

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
        let staleWindow = BrowserPresentedSession(
            session: saved, selection: showing(try XCTUnwrap(saved.space(id: target.id))))
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

    func testPortableImportPreservesCollidingNativeImagesAndCommitsWithItsSyncJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try BrowserTransactionalSessionPersistence(url: directory.appendingPathComponent("session.sqlite"), favicons: InMemoryBrowserFaviconStore())
        var original = BrowserSession.preview
        original.spaces[0].tabs[0].faviconData = Data([1, 2])
        var imported = original.spaces[0]
        imported.tabs[0].faviconData = Data([3, 4])
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try storage.migrateIfNeeded(session: original, journal: journal)
        let sync = BrowserSyncCoordinator(persistence: storage.journalPersistence)
        let store = BrowserStore(session: original, persistence: storage, syncCoordinator: sync)
        let other = store.makeWindowStore()
        try store.importPortableArchive(BrowserPortableImport(spaces: [imported], summary: .init(
            spaceCount: 1, folderCount: imported.folders.count, liveTabCount: imported.tabs.count,
            archivedTabCount: 0, historyEntryCount: 0)))
        let added = try XCTUnwrap(store.session.spaces.last)
        XCTAssertNotEqual(added.id, imported.id)
        XCTAssertEqual(store.selectedSpaceID, added.id)
        XCTAssertNotEqual(added.profile, imported.profile)
        XCTAssertNotEqual(added.tabs[0].id, imported.tabs[0].id)
        XCTAssertEqual(store.session.spaces[0].tabs[0].faviconData, Data([1, 2]))
        XCTAssertEqual(added.tabs[0].faviconData, Data([3, 4]))
        XCTAssertEqual(other.session.spaces, store.session.spaces)
        XCTAssertEqual(storage.load(), store.session)
        XCTAssertEqual(try storage.journalPersistence.load(), sync.journal)
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
        original.spaces[0].history.append(visit("https://example.org/before", title: "Before"))
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        try storage.migrateIfNeeded(session: original, journal: journal)
        let core = BrowserCoreSessionAuthority(session: original)
        var next = original
        next.spaces[0].name = "After transaction"
        next.spaces[0].history.append(visit("https://example.org/after", title: "After"))
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
        let original = BrowserSession(spaces: [first, second])
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
        XCTAssertNil(other.selectedTabID(in: id))
        store.setDefaultSpace(id)
        store.addSpace()
        XCTAssertEqual(store.session.spaces.count, session.spaces.count + 1)
        XCTAssertEqual(other.session.spaces.count, store.session.spaces.count)
        XCTAssertEqual(other.selectedSpaceID, id)
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

    func testDirectCommandsKeepAssetsAndCheckpointNoWindowSelection() throws {
        var original = BrowserSession.preview
        let spaceID = original.spaces[0].id
        let tabID = original.spaces[0].tabs[0].id
        let icon = Data([1, 2, 3])
        original.spaces[0].tabs[0].faviconData = icon
        original.spaces[0].history.append(visit("https://example.org/direct", title: "Visit"))
        let core = BrowserCoreSessionAuthority(session: original)
        let view = BrowserStoreSelection(selectedSpaceID: original.spaces[1].id)
        _ = try core.execute("tab.rename", in: spaceID,
            arguments: ["tabId": tabID.rawValue.uuidString, "title": "Core command"], view: view, at: .now)
        XCTAssertEqual(core.projection.spaces[0].tabs[0].faviconData, icon)
        XCTAssertEqual(core.projection.spaces[0].history, original.spaces[0].history)
        let checkpoint = try core.checkpoint()
        let coreData = try XCTUnwrap(checkpoint.coreData())
        let restored = try JSONDecoder().decode(BrowserSession.self, from: coreData)
        XCTAssertEqual(restored.spaces[0].tabs[0].customTitle, "Core command")
        XCTAssertNil(BrowserLegacySessionSelection.decode(coreData), "A checkpoint never stores a window's selection")
    }

    func testCoreCheckpointPersistsTheCapturedRevision() async throws {
        let suite = "crest.core-authority-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let icons = InMemoryBrowserFaviconStore()
        let persistence = UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: icons)
        var original = BrowserSession.preview
        original.spaces[0].history.append(visit("https://example.org/checkpoint", title: "Checkpoint"))
        let core = BrowserCoreSessionAuthority(session: original)
        let checkpoint = try core.checkpoint()
        var next = original
        next.spaces[0].tabs[0].customTitle = "Edited after snapshot"
        next.spaces[0].history = []
        next.spaces.removeLast()
        try core.replaceDurably(with: next) { _ in }
        persistence.save(original, scope: .everything, checkpoint: checkpoint)
        await persistence.flushPendingSaves()
        let restored = UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: icons).load()
        XCTAssertEqual(restored, original)
        XCTAssertEqual(core.projection, next)
    }

    /// An installed release kept the viewed Space and each Space's tab inside
    /// its stored session. That session still loads, its selection opens the
    /// launch window and folds once into a window record written before windows
    /// captured their Spaces, and the checkpoint written next holds none of it.
    func testLegacyStoredSelectionLoadsFoldsOnceAndLeavesTheCheckpoint() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "crest.core-authority-test.legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let icons = InMemoryBrowserFaviconStore()
        let installed = BrowserSession.preview
        XCTAssertNil(installed.defaultSpaceID, "Launch prefers a default Space over the stored one")
        let space = installed.spaces[1]
        let tab = try XCTUnwrap(space.tabs.first { $0.id != BrowserStoreSelection.fallbackTabID(in: space) })
        let writer = UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: icons)
        writer.save(installed, scope: .everything)
        await writer.flushPendingSaves()
        // Spell the installed release's selection into its stored core.
        func json<Value: Encodable>(_ value: Value) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
        }
        let storedCore = try XCTUnwrap(defaults.data(forKey: UserDefaultsBrowserSessionPersistence.coreKey))
        var core = try XCTUnwrap(JSONSerialization.jsonObject(with: storedCore) as? [String: Any])
        var spaces = try XCTUnwrap(core["spaces"] as? [[String: Any]])
        core["selectedSpaceID"] = try json(space.id)
        spaces[1]["selectedTabID"] = try json(tab.id)
        core["spaces"] = spaces
        defaults.set(try JSONSerialization.data(withJSONObject: core), forKey: UserDefaultsBrowserSessionPersistence.coreKey)

        let storage = try BrowserStore.migratedStorage(directory: directory,
            legacy: UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: icons),
            journal: UserDefaultsBrowserSyncJournalPersistence(defaults: defaults), favicons: icons,
            environment: .current)
        let session = try XCTUnwrap(storage.load())
        XCTAssertEqual(session, installed)
        let launch = try XCTUnwrap(storage.loadLegacySelection()).launchSelection(in: session)
        XCTAssertEqual(launch.selectedSpaceID, space.id)
        XCTAssertEqual(launch.selectedTabID(in: space.id), tab.id)

        var window = BrowserWindowState(selectedSpaceID: space.id, selectedTabIDsBySpace: [:])
        window.foldLegacySelection(launch, in: session)
        XCTAssertEqual(window.selection.selectedTabID(in: space.id), tab.id)
        let folded = window
        window.foldLegacySelection(BrowserStoreSelection(selectedSpaceID: space.id), in: session)
        XCTAssertEqual(window, folded, "A record folds the legacy selection only once")

        let store = BrowserStore(session: session, selection: launch, persistence: storage)
        store.saveLaunchCheckpoint()
        await storage.flushPendingSaves()
        let relaunched = try BrowserTransactionalSessionPersistence(url: storage.url, favicons: icons)
        XCTAssertEqual(relaunched.load(), store.session)
        XCTAssertNil(relaunched.loadLegacySelection(), "The next checkpoint must not write the selection back")
    }

    // MARK: - Fixtures

    /// A window showing `space` on its fallback tab.
    private func showing(_ space: BrowserSpace) -> BrowserStoreSelection {
        var selection = BrowserStoreSelection(selectedSpaceID: space.id)
        selection.selectSpace(space)
        return selection
    }

    private func visit(_ address: String, title: String) -> BrowserHistoryEntry {
        BrowserHistoryEntry(url: URL(string: address)!, title: title, firstVisitedAt: .now, lastVisitedAt: .now)
    }
}
