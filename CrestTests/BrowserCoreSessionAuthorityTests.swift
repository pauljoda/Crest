import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCoreSessionAuthorityTests: XCTestCase {
    func testBatchDeletionCommitsExplicitTombstonesWithSavedTabRemoval() throws {
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
        let harness = try BrowserStoredSessionHarness(
            session: original, journal: journal, selection: showing(original.spaces[0]))
        let store = harness.store
        let request = BrowserTabBatchRequest(ids: tabs.map(\.id), in: store.session.spaces[0])
        try store.commitTabBatch(request, action: .delete)
        // The batch is on disk with its journal when the command returns.
        let (saved, committed) = try harness.stored()
        XCTAssertTrue(saved.spaces[0].tabs.allSatisfy { !ids.contains($0.id) })
        XCTAssertEqual(saved, store.session)
        XCTAssertEqual(committed, store.syncCoordinator?.journal)
        for tab in tabs {
            let id = BrowserSyncRecordID(kind: .tab, value: tab.id.rawValue)
            let record = try XCTUnwrap(committed?.records.first { $0.id == id })
            XCTAssertEqual(record.tombstone?.reason, .explicitDelete)
        }
    }

    func testRecordCommandsPreserveNativeAssetsAndOtherWindowSelection() throws {
        var original = BrowserSession.preview
        let spaceID = original.spaces[0].id
        original.spaces[0].history = []
        var archived = BrowserTab(
            title: "Archived", url: URL(string: "https://example.org/archive"), placement: .current)
        archived.faviconData = Data([1, 3, 5])
        original.spaces[0].archivedTabs = [ArchivedTab(tab: archived, archivedAt: .now, reason: .closed)]
        let store = BrowserStore(session: original, selection: showing(original.spaces[0]))
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
        XCTAssertEqual(
            store.session.space(id: spaceID)?.archivedTabs.first(where: { $0.id == archived.id })?.tab.faviconData,
            archived.faviconData)
        XCTAssertNil(store.localSyncErrorDescription)
    }

    func testFailedTransferStorageReleasesBothWritersWhileThePreparedValueIsStillAlive() throws {
        let original = BrowserSession.preview
        let harness = try BrowserStoredSessionHarness(session: original)
        let source = harness.store
        let assignment = BrowserSpaceRuntimeAssignment(space: source.session.spaces[0])
        let tab = source.session.spaces[0].tabs[0]
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let before = source.session
        let empty = temporary.session
        try harness.refuseWrites(to: "core")
        XCTAssertFalse(source.transferTab(tab.id, matching: assignment, to: temporary, in: assignment))
        XCTAssertEqual(source.session, before)
        XCTAssertEqual(temporary.session, empty)
        XCTAssertEqual(try harness.stored().session, before)
        try harness.acceptWrites()
        XCTAssertTrue(source.transferTab(tab.id, matching: assignment, to: temporary, in: assignment))
        XCTAssertFalse(source.session.tabIDs.contains(tab.id))
        XCTAssertEqual(temporary.selectedTab?.id, tab.id)
        XCTAssertEqual(try harness.stored().session, source.session)
    }

    func testWorkspaceTransferSavesThePersistentOwnerAndJournalTogetherBeforeReconcilingWindows() throws {
        var original = BrowserSession.preview
        let spaceID = original.spaces[0].id
        let tabID = original.spaces[0].tabs[0].id
        original.spaces[0].tabs[0].faviconData = Data([5, 8, 13])
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        let harness = try BrowserStoredSessionHarness(session: original, journal: journal)
        let source = harness.store
        let sync = try XCTUnwrap(source.syncCoordinator)
        let observer = source.makeWindowStore()
        let assignment = BrowserSpaceRuntimeAssignment(space: original.spaces[0])
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        XCTAssertTrue(source.transferTab(tabID, matching: assignment, to: temporary, in: assignment))
        XCTAssertFalse(observer.session.tabIDs.contains(tabID))
        XCTAssertEqual(try harness.stored().session, source.session)
        XCTAssertEqual(try harness.stored().journal, sync.journal)
        XCTAssertEqual(temporary.selectedTab?.faviconData, Data([5, 8, 13]))
        XCTAssertFalse(source.session.space(id: spaceID)!.archivedTabs.contains { $0.id == tabID })
        XCTAssertTrue(temporary.transferTab(tabID, matching: assignment, to: source, in: assignment))
        XCTAssertEqual(source.selectedTab?.id, tabID)
        XCTAssertTrue(observer.session.tabIDs.contains(tabID))
        XCTAssertEqual(try harness.stored().session, source.session)
        XCTAssertEqual(try harness.stored().journal, sync.journal)
        XCTAssertEqual(source.selectedTab?.faviconData, Data([5, 8, 13]))
    }

    func testDeletionIntentSurvivesAdapterFailureAndRestartThenCommitsItsTombstoneWithTheSession() async throws {
        let original = BrowserSession.preview
        let target = original.spaces[0]
        var initialJournal = BrowserSyncJournal()
        try initialJournal.stage(session: original)
        let harness = try BrowserStoredSessionHarness(session: original, journal: initialJournal)
        let store = harness.store
        let other = store.makeWindowStore()
        let failing = DeletionAdapter { space in
            // The intent is on disk before the engine erases anything.
            let intent = try XCTUnwrap(try harness.stored().session.spaceDeletions?.first)
            XCTAssertEqual(intent.spaceID, space.id)
            XCTAssertEqual(intent.profileID, space.profile.id)
            XCTAssertTrue(other.deletingSpaceIDs.contains(space.id))
            XCTAssertNotEqual(other.selectedSpace?.id, space.id)
            throw DeletionFailure.interrupted
        }
        do {
            try await store.deleteSpace(target.id, dataDeleter: failing)
            XCTFail("Expected adapter failure")
        } catch DeletionFailure.interrupted {}
        XCTAssertTrue(store.deletingSpaceIDs.contains(target.id))
        let saved = try harness.stored().session
        XCTAssertNotNil(saved.space(id: target.id))
        let staleWindow = BrowserPresentedSession(
            session: saved, selection: showing(try XCTUnwrap(saved.space(id: target.id))))
        let pages = BrowserPagePool()
        pages.select(session: staleWindow)
        XCTAssertNil(pages.activePage, "A restored window must not reopen a pending profile")
        let relaunched = try await harness.relaunch()
        let restarted = relaunched.store
        let restartedSync = try XCTUnwrap(restarted.syncCoordinator)
        XCTAssertTrue(restarted.deletingSpaceIDs.contains(target.id))
        XCTAssertNotEqual(restarted.selectedSpace?.id, target.id)
        let succeeding = DeletionAdapter { space in XCTAssertEqual(space.profile.id, target.profile.id) }
        await restarted.resumePendingSpaceDeletions(dataDeleter: succeeding)
        XCTAssertEqual(succeeding.calls, [target.id])
        XCTAssertNil(restarted.session.space(id: target.id))
        XCTAssertNil(restarted.session.spaceDeletions)
        XCTAssertEqual(try relaunched.stored().session, restarted.session)
        XCTAssertEqual(try relaunched.stored().journal, restartedSync.journal)
        let tombstones = restartedSync.journal.records.filter { $0.spaceID == target.id && $0.tombstone != nil }
        XCTAssertFalse(tombstones.isEmpty)
        XCTAssertTrue(tombstones.allSatisfy { $0.tombstone?.reason == .explicitDelete })
    }

    func testRemoteSpaceDeletionDurablySchedulesTheRegisteredAdapterAndRetriesFailure() async throws {
        let original = BrowserSession.preview
        let target = original.spaces[0]
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        let harness = try BrowserStoredSessionHarness(session: original, journal: journal)
        let store = harness.store
        let sync = try XCTUnwrap(store.syncCoordinator)
        let other = store.makeWindowStore()
        var fail = true
        let adapter = DeletionAdapter { space in
            XCTAssertEqual(space.profile.id, target.profile.id)
            let stored = try harness.stored()
            XCTAssertEqual(stored.session.spaceDeletions?.first?.spaceID, target.id)
            let records = try XCTUnwrap(stored.journal).records
            XCTAssertTrue(
                records.contains {
                    $0.spaceID == target.id && $0.id.kind == .space && $0.tombstone?.reason == .explicitDelete
                })
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
        XCTAssertNotNil(try harness.stored().session.spaceDeletions?.first)
        fail = false
        try store.mergeRemoteSyncRecords(incoming.records)
        await store.family.spaceCleanupTask?.value
        XCTAssertEqual(adapter.calls, [target.id, target.id])
        XCTAssertNil(store.session.space(id: target.id))
        XCTAssertNil(store.session.spaceDeletions)
        XCTAssertEqual(try harness.stored().session, store.session)
        XCTAssertEqual(try harness.stored().journal, sync.journal)
        XCTAssertEqual(other.session.spaces.map(\.id), store.session.spaces.map(\.id))
    }

    func testPortableImportPreservesCollidingNativeImagesAndCommitsWithItsSyncJournal() throws {
        var original = BrowserSession.preview
        original.spaces[0].tabs[0].faviconData = Data([1, 2])
        var imported = original.spaces[0]
        imported.tabs[0].faviconData = Data([3, 4])
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        let harness = try BrowserStoredSessionHarness(session: original, journal: journal)
        let store = harness.store
        let sync = try XCTUnwrap(store.syncCoordinator)
        let other = store.makeWindowStore()
        try store.importPortableArchive(
            BrowserPortableImport(
                spaces: [imported],
                summary: .init(
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
        XCTAssertEqual(try harness.stored().session, store.session)
        XCTAssertEqual(try harness.stored().journal, sync.journal)
    }

    private enum DeletionFailure: Error { case interrupted }
    private final class DeletionAdapter: BrowserSpaceDataDeleting {
        var calls: [SpaceID] = []
        let action: (BrowserSpace) throws -> Void
        init(action: @escaping (BrowserSpace) throws -> Void) { self.action = action }
        func deleteData(for space: BrowserSpace) async throws {
            calls.append(space.id)
            try action(space)
        }
    }

    func testIncomingSyncPublishesAndPersistsTheSameSessionAcrossWindows() async throws {
        let original = BrowserSession.preview
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        let harness = try BrowserStoredSessionHarness(session: original, journal: journal)
        let store = harness.store
        let coordinator = try XCTUnwrap(store.syncCoordinator)
        let other = store.makeWindowStore()
        var remote = original
        remote.spaces[0].name = "Remote Space"
        var remoteJournal = journal
        try remoteJournal.stage(session: remote)
        try store.mergeRemoteSyncRecords(remoteJournal.records)
        XCTAssertEqual(store.session.spaces[0].name, "Remote Space")
        XCTAssertEqual(other.session.spaces[0].name, "Remote Space")
        // The merge and its journal are on disk when the merge returns.
        XCTAssertEqual(try harness.stored().session, store.session)
        XCTAssertEqual(try harness.stored().journal, coordinator.journal)
        // A local edit is saved behind; staging it and the flush a window
        // waits for put both on disk.
        store.updateSpaceIdentity(original.spaces[0].id, name: "Local after sync", symbol: "book", accent: .teal)
        await store.flushPendingSyncPersistence()
        let restored = try harness.stored()
        XCTAssertEqual(restored.session.spaces[0].name, "Local after sync")
        XCTAssertEqual(restored.journal, coordinator.journal)
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
        let store = BrowserStore(session: session)
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

    func testDirectCommandsKeepAssetsAndSaveNoWindowSelection() async throws {
        var original = BrowserSession.preview
        let spaceID = original.spaces[0].id
        let tabID = original.spaces[0].tabs[0].id
        let icon = Data([1, 2, 3])
        original.spaces[0].tabs[0].faviconData = icon
        original.spaces[0].history.append(visit("https://example.org/direct", title: "Visit"))
        let harness = try BrowserStoredSessionHarness(
            session: original, selection: BrowserStoreSelection(selectedSpaceID: original.spaces[1].id))
        let store = harness.store
        XCTAssertTrue(store.setTabCustomTitle("Core command", for: tabID, in: spaceID))
        XCTAssertEqual(store.session.spaces[0].tabs[0].faviconData, icon)
        XCTAssertEqual(store.session.spaces[0].history, original.spaces[0].history)
        await store.flushPendingSyncPersistence()
        let saved = try XCTUnwrap(try harness.storedPart("core"))
        let restored = try JSONDecoder().decode(BrowserSession.self, from: saved)
        XCTAssertEqual(restored.spaces[0].tabs[0].customTitle, "Core command")
        XCTAssertNil(BrowserLegacySessionSelection.decode(saved), "A save never stores a window's selection")
    }

    /// An installed release kept the viewed Space and each Space's tab inside
    /// its stored session. That session still loads, its selection opens the
    /// launch window and folds once into a window record written before windows
    /// captured their Spaces, and the session saved next holds none of it.
    func testLegacyStoredSelectionLoadsFoldsOnceAndLeavesTheSavedSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "crest.core-authority-test.legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let icons = InMemoryBrowserFaviconStore()
        var installed = BrowserSession.preview
        // Launch repair always names a launch Space, so launch opens it and only
        // the stored per-Space tabs come from the older selection.
        installed.defaultSpaceID = installed.spaces[0].id
        let space = installed.spaces[1]
        let tab = try XCTUnwrap(space.tabs.first { $0.id != BrowserStoreSelection.fallbackTabID(in: space) })
        let writer = UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: icons)
        writer.save(installed)
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
        defaults.set(
            try JSONSerialization.data(withJSONObject: core), forKey: UserDefaultsBrowserSessionPersistence.coreKey)

        let crest = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let stored = try BrowserStore.migratedStorage(
            core: crest, legacy: UserDefaultsBrowserSessionPersistence(defaults: defaults, faviconStore: icons),
            journal: UserDefaultsBrowserSyncJournalPersistence(defaults: defaults), favicons: icons,
            seed: .freshInstallSeed, environment: .current)
        let session = stored.authority.projection
        XCTAssertEqual(session, installed)
        let launch = try XCTUnwrap(stored.legacySelection).launchSelection(in: session)
        XCTAssertEqual(launch.selectedSpaceID, installed.defaultSpaceID)
        XCTAssertEqual(launch.selectedTabID(in: space.id), tab.id)

        var window = BrowserWindowState(selectedSpaceID: space.id, selectedTabIDsBySpace: [:])
        window.foldLegacySelection(launch, in: session)
        XCTAssertEqual(window.selection.selectedTabID(in: space.id), tab.id)
        let folded = window
        window.foldLegacySelection(BrowserStoreSelection(selectedSpaceID: space.id), in: session)
        XCTAssertEqual(window, folded, "A record folds the legacy selection only once")

        let store = BrowserStore.production(
            stored: stored, core: crest, favicons: icons, credentialVault: InMemoryCredentialVault())
        await store.flushPendingSyncPersistence()
        let relaunched = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let reopened = try XCTUnwrap(try BrowserCoreStoredSession.load(core: relaunched, favicons: icons))
        XCTAssertEqual(reopened.authority.projection, store.session)
        XCTAssertNil(reopened.legacySelection, "The next save must not write the selection back")
    }

    /// Tab images stay native assets beside the core's file: a captured icon
    /// reaches the favicon store, a relaunch reattaches it, and a deleted tab's
    /// image is pruned.
    func testTabImagesFollowTheSessionIntoTheFaviconStore() async throws {
        let harness = try BrowserStoredSessionHarness(session: .preview)
        let store = harness.store
        let spaceID = try XCTUnwrap(store.selectedSpace?.id)
        let tab = try XCTUnwrap(store.selectedSpace?.tabs.first { $0.url != nil })
        let icon = Data("captured".utf8)
        store.cacheAutomaticTabFavicon(icon, iconAccent: nil, url: try XCTUnwrap(tab.url), for: tab.id, in: spaceID)
        XCTAssertEqual(harness.favicons.favicon(tabID: tab.id), icon)
        let relaunched = try await harness.relaunch()
        XCTAssertEqual(relaunched.store.session.space(id: spaceID)?.tabs.first { $0.id == tab.id }?.faviconData, icon)
        store.deleteTab(tab.id, in: spaceID)
        XCTAssertNil(harness.favicons.favicon(tabID: tab.id))
    }

    /// The Start Page a launch presents is an ordinary current tab once the
    /// core saves it: the next launch presents that same tab again rather than
    /// adding another, so relaunching never piles up Start Pages.
    func testALaunchStartPageIsReusedAcrossRelaunches() async throws {
        var session = BrowserSession.preview
        for index in session.spaces.indices { session.spaces[index].tabs.removeAll(where: \.isStartPage) }
        var harness = try BrowserStoredSessionHarness(session: session)
        let spaceID = try XCTUnwrap(harness.store.selectedSpace?.id)
        let draft = try XCTUnwrap(harness.store.presentStartPageForLaunch())
        for _ in 0..<3 {
            harness = try await harness.relaunch()
            let store = harness.store
            store.selectSpace(spaceID)
            XCTAssertEqual(store.presentStartPageForLaunch(), draft)
            let space = try XCTUnwrap(store.session.space(id: spaceID))
            XCTAssertEqual(space.tabs.filter(\.isStartPage).map(\.id), [draft])
        }
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
