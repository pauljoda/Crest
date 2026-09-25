import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCoreSessionAuthorityTests: XCTestCase {
    func testBatchDeletionCommitsExplicitTombstonesWithSavedTabRemoval() async throws {
        var original = BrowserSession.preview
        let tabs = Array(original.spaces[0].tabs.filter { $0.url != nil && !$0.isStartPage }.prefix(2))
        XCTAssertEqual(tabs.count, 2)
        let ids = Set(tabs.map(\.id))
        for index in original.spaces[0].tabs.indices where ids.contains(original.spaces[0].tabs[index].id) {
            original.spaces[0].tabs[index].placement = .saved
            original.spaces[0].tabs[index].folderID = nil
            original.spaces[0].tabs[index].splitGroupID = nil
        }
        let harness = try await BrowserStoredSessionHarness.staged(original)
        let store = harness.store
        store.selectSpace(original.spaces[0].id)
        let request = try XCTUnwrap(store.capturedSelection(ids: tabs.map(\.id)))
        try store.send(store.deleting(request), for: request)
        // The batch is on disk with its journal when the command returns.
        let (saved, committed) = try harness.stored()
        XCTAssertTrue(saved.spaces[0].tabs.allSatisfy { !ids.contains($0.id) })
        XCTAssertEqual(saved, store.session)
        XCTAssertTrue(try harness.storedJournalIsPublished())
        for tab in tabs {
            let record = try XCTUnwrap(committed?.record(.tab, tab.id))
            XCTAssertEqual(record.deletionReason, .explicitDelete)
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
        let store = BrowserStore(
            session: original, showing: original.spaces[0].id, tabs: fallbackTabs(original.spaces[0]),
            core: .hostingPages())
        let other = store.makeWindowStore()
        other.selectSpace(original.spaces[1].id)
        let otherSpace = other.selectedSpace?.id
        let otherTab = other.selectedTab?.id

        // A page's recorded visits reach every window of the workspace.
        let page = try XCTUnwrap(store.openReportingPage(for: nil))
        store.finishNavigation(
            of: page, to: try XCTUnwrap(URL(string: "https://example.org/visit#one")), titled: "First")
        let visit = try XCTUnwrap(store.selectedSpace?.history.first)
        store.finishNavigation(
            of: page, to: try XCTUnwrap(URL(string: "https://example.org/visit#two")), titled: "Second")
        XCTAssertEqual(store.selectedSpace?.history.first?.id, visit.id)
        XCTAssertEqual(store.selectedSpace?.history.first?.visitCount, 2)
        XCTAssertEqual(other.session.space(id: spaceID)?.history, store.selectedSpace?.history)

        store.restoreArchivedTab(archived.id)
        XCTAssertEqual(store.selectedTab?.id, archived.id)
        XCTAssertEqual(store.selectedTab?.faviconData, archived.faviconData)
        XCTAssertTrue(try XCTUnwrap(other.session.space(id: spaceID)).archivedTabs.isEmpty)
        XCTAssertEqual(other.selectedSpace?.id, otherSpace)
        XCTAssertEqual(other.selectedTab?.id, otherTab)

        // Closing the restored tab archives it again, with its image.
        store.selectTab(original.spaces[0].tabs[0].id)
        XCTAssertTrue(store.closeTab(archived.id, in: spaceID))
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

    func testWorkspaceTransferSavesThePersistentOwnerAndJournalTogetherBeforeReconcilingWindows() async throws {
        var original = BrowserSession.preview
        let spaceID = original.spaces[0].id
        let tabID = original.spaces[0].tabs[0].id
        original.spaces[0].tabs[0].faviconData = Data([5, 8, 13])
        let harness = try await BrowserStoredSessionHarness.staged(original)
        let source = harness.store
        let observer = source.makeWindowStore()
        let assignment = BrowserSpaceRuntimeAssignment(space: original.spaces[0])
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        XCTAssertTrue(source.transferTab(tabID, matching: assignment, to: temporary, in: assignment))
        XCTAssertFalse(observer.session.tabIDs.contains(tabID))
        XCTAssertEqual(try harness.stored().session, source.session)
        XCTAssertTrue(try harness.storedJournalIsPublished())
        XCTAssertEqual(temporary.selectedTab?.faviconData, Data([5, 8, 13]))
        XCTAssertFalse(source.session.space(id: spaceID)!.archivedTabs.contains { $0.id == tabID })
        XCTAssertTrue(temporary.transferTab(tabID, matching: assignment, to: source, in: assignment))
        XCTAssertEqual(source.selectedTab?.id, tabID)
        XCTAssertTrue(observer.session.tabIDs.contains(tabID))
        XCTAssertEqual(try harness.stored().session, source.session)
        XCTAssertTrue(try harness.storedJournalIsPublished())
        XCTAssertEqual(source.selectedTab?.faviconData, Data([5, 8, 13]))
    }

    func testDeletionIntentSurvivesAdapterFailureAndRestartThenCommitsItsTombstoneWithTheSession() async throws {
        let original = BrowserSession.preview
        let target = original.spaces[0]
        let harness = try await BrowserStoredSessionHarness.staged(original)
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
            session: saved,
            window: .preview(showing: target.id, tabs: fallbackTabs(try XCTUnwrap(saved.space(id: target.id)))))
        // The window's pages open through the core, which hosts them on WebKit
        // and refuses a page in a Space whose deletion is pending.
        harness.core.engines.register(WebKitEngineBinding(), isDefault: true)
        let pages = BrowserPagePool(browser: store)
        pages.select(session: staleWindow)
        XCTAssertNil(pages.activePage, "A restored window must not reopen a pending profile")
        let relaunched = try await harness.relaunch()
        let restarted = relaunched.store
        XCTAssertTrue(restarted.deletingSpaceIDs.contains(target.id))
        XCTAssertNotEqual(restarted.selectedSpace?.id, target.id)
        let succeeding = DeletionAdapter { space in XCTAssertEqual(space.profile.id, target.profile.id) }
        await restarted.resumePendingSpaceDeletions(dataDeleter: succeeding)
        XCTAssertEqual(succeeding.calls, [target.id])
        XCTAssertNil(restarted.session.space(id: target.id))
        XCTAssertNil(restarted.session.spaceDeletions)
        XCTAssertEqual(try relaunched.stored().session, restarted.session)
        XCTAssertTrue(try relaunched.storedJournalIsPublished())
        let targetRecords = try relaunched.storedJournal().records.filter { $0.spaceID == target.id }
        let tombstones = targetRecords.filter(\.isTombstone)
        XCTAssertFalse(tombstones.isEmpty)
        XCTAssertTrue(tombstones.allSatisfy { $0.deletionReason == .explicitDelete })
    }

    func testRemoteSpaceDeletionDurablySchedulesTheRegisteredAdapterAndRetriesFailure() async throws {
        let original = BrowserSession.preview
        let target = original.spaces[0]
        let harness = try await BrowserStoredSessionHarness.staged(original)
        let store = harness.store
        let other = store.makeWindowStore()
        var fail = true
        let adapter = DeletionAdapter { space in
            XCTAssertEqual(space.profile.id, target.profile.id)
            let stored = try harness.stored()
            XCTAssertEqual(stored.session.spaceDeletions?.first?.spaceID, target.id)
            let record = try XCTUnwrap(try XCTUnwrap(stored.journal).record(.space, target.id))
            XCTAssertEqual(record.deletionReason, .explicitDelete)
            XCTAssertTrue(other.deletingSpaceIDs.contains(target.id))
            XCTAssertNotEqual(other.selectedSpace?.id, target.id)
            if fail { throw DeletionFailure.interrupted }
        }
        store.family.configureSpaceDataCleanup(adapter, from: store)
        // Another device that holds the same records deletes the Space.
        let remote = try await harness.joiningDevice()
        try await remote.store.deleteSpace(target.id, dataDeleter: DeletionAdapter { _ in })
        let incoming = try await remote.pendingRecords()
        // The adapter checks that the deletion and its tombstone are on disk
        // before any cleanup runs.
        try await harness.deliver(MergeSyncRecords(records: incoming))
        await store.family.spaceCleanupTask?.value
        XCTAssertEqual(adapter.calls, [target.id])
        XCTAssertNotNil(try harness.stored().session.spaceDeletions?.first)
        fail = false
        try await harness.deliver(MergeSyncRecords(records: incoming))
        await store.family.spaceCleanupTask?.value
        XCTAssertEqual(adapter.calls, [target.id, target.id])
        XCTAssertNil(store.session.space(id: target.id))
        XCTAssertNil(store.session.spaceDeletions)
        XCTAssertEqual(try harness.stored().session, store.session)
        XCTAssertTrue(try harness.storedJournalIsPublished())
        XCTAssertEqual(other.session.spaces.map(\.id), store.session.spaces.map(\.id))
    }

    func testPortableImportPreservesCollidingNativeImagesAndCommitsWithItsSyncJournal() async throws {
        var original = BrowserSession.preview
        original.spaces[0].tabs[0].faviconData = Data([1, 2])
        var imported = original.spaces[0]
        imported.tabs[0].faviconData = Data([3, 4])
        let harness = try await BrowserStoredSessionHarness.staged(original)
        let store = harness.store
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
        XCTAssertTrue(try harness.storedJournalIsPublished())
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

    /// A merge the transport sends from its own thread is on disk with its
    /// journal when it returns, and reaches every window through the wake and
    /// one drain.
    func testIncomingSyncPublishesAndPersistsTheSameSessionAcrossWindows() async throws {
        let original = BrowserSession.preview
        let harness = try await BrowserStoredSessionHarness.staged(original)
        let store = harness.store
        let other = store.makeWindowStore()
        // Another device that holds the same records renames the Space.
        let remote = try await harness.joiningDevice()
        let space = original.spaces[0]
        remote.store.updateSpaceIdentity(space.id, name: "Remote Space", symbol: space.symbol, accent: space.accent)
        let core = harness.core
        let merge = MergeSyncRecords(records: try await remote.pendingRecords())
        try await Task.detached { _ = try core.deliver(merge) }.value
        // The merge and its journal are on disk when the merge returns.
        XCTAssertEqual(try harness.stored().session.spaces[0].name, "Remote Space")
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(store.session.spaces[0].name, "Remote Space")
        XCTAssertEqual(other.session.spaces[0].name, "Remote Space")
        XCTAssertEqual(try harness.stored().session, store.session)
        XCTAssertTrue(try harness.storedJournalIsPublished())
        // A local edit is saved behind; staging it and the flush a window
        // waits for put both on disk.
        store.updateSpaceIdentity(original.spaces[0].id, name: "Local after sync", symbol: "book", accent: .teal)
        await store.flushPendingSyncPersistence()
        let restored = try harness.stored()
        XCTAssertEqual(restored.session.spaces[0].name, "Local after sync")
        XCTAssertTrue(try harness.storedJournalIsPublished())
    }

    /// Quitting and backgrounding wait for this flush and nothing after it:
    /// edits accepted just before are on disk and staged for sync once it
    /// returns, though a rename stages only after a coalescing delay and a new
    /// tab only once the turn that opened it ends.
    func testFlushLeavesTheLastEditsSavedAndStagedForSync() async throws {
        let harness = try await BrowserStoredSessionHarness.staged(.preview)
        let store = harness.store
        let window = store.makeWindowStore(BrowserWindowOpening(saved: true))
        await store.flushPendingSyncPersistence()
        try harness.acknowledgePendingUploads()
        XCTAssertEqual(try harness.stored().journal?.pending.isEmpty, true)
        XCTAssertEqual(try harness.storedShownSpace(of: window.windowID), window.selectedSpaceID)

        let space = store.session.spaces[0]
        store.updateSpaceIdentity(space.id, name: "Renamed before quit", symbol: "book", accent: .teal)
        let url = try XCTUnwrap(URL(string: "https://example.org/opened-before-quit"))
        let opened = try XCTUnwrap(store.openNewTab(url: url, in: space.id, selecting: true))
        // Showing another Space changes only the window's record, never the session.
        let shown = try XCTUnwrap(store.session.spaces.first { $0.id != window.selectedSpaceID })
        window.selectPresentedSpace(shown.id)
        await store.flushPendingSyncPersistence()

        let stored = try harness.stored()
        XCTAssertEqual(stored.session.space(id: space.id)?.name, "Renamed before quit")
        XCTAssertEqual(stored.session.space(id: space.id)?.tabs.contains { $0.id == opened }, true)
        let journal = try XCTUnwrap(stored.journal)
        XCTAssertTrue(journal.isPending(.space, space.id))
        XCTAssertTrue(journal.isPending(.tab, opened))
        XCTAssertEqual(try harness.storedShownSpace(of: window.windowID), shown.id)
    }

    func testCoreRepairPreservesAssetOwnershipWhenIdentitiesCollide() throws {
        var first = BrowserSession.preview.spaces[0]
        first.tabs = [first.tabs[0]]
        first.tabs[0].faviconData = Data([1])
        var second = first
        second.tabs[0].faviconData = Data([2])
        let original = BrowserSession(spaces: [first, second])
        let repaired = try original.openedAsSeed()
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
        let other = store.makeWindowStore(BrowserWindowOpening(restoresTabs: false))
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
        let harness = try BrowserStoredSessionHarness(session: original)
        let store = harness.store
        store.selectPresentedSpace(original.spaces[1].id)
        XCTAssertTrue(store.setTabCustomTitle("Core command", for: tabID, in: spaceID))
        XCTAssertEqual(store.session.spaces[0].tabs[0].faviconData, icon)
        XCTAssertEqual(store.session.spaces[0].history, original.spaces[0].history)
        await store.flushPendingSyncPersistence()
        let saved = try XCTUnwrap(try harness.storedPart("core"))
        let restored = try JSONDecoder().decode(BrowserSession.self, from: saved)
        XCTAssertEqual(restored.spaces[0].tabs[0].customTitle, "Core command")
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let spaces = try XCTUnwrap(stored["spaces"] as? [[String: Any]])
        XCTAssertNil(stored["selectedSpaceID"], "A save never stores a window's selection")
        XCTAssertTrue(spaces.allSatisfy { $0["selectedTabID"] == nil })
    }

    /// An installed release kept the viewed Space and each Space's tab inside
    /// its stored session, and each window's record in its defaults. The
    /// session still loads; a window without a record opens on the launch Space
    /// with the tabs the release showed, a record written before windows
    /// remembered their Spaces folds them in once, its sidebar layout comes
    /// across, and the session saved next holds none of it.
    func testLegacyStoredSelectionAndWindowRecordsComeAcrossOnceAndLeaveTheSavedSession() async throws {
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
        let tab = try XCTUnwrap(space.tabs.first { $0.id != CrestCore().fallbackTabID(in: space) })
        try BrowserInstalledRelease.write(installed, to: defaults, favicons: icons)
        // Spell the installed release's selection into its stored core.
        func json<Value: Encodable>(_ value: Value) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
        }
        let storedCore = try XCTUnwrap(defaults.data(forKey: BrowserLegacySessionDefaults.coreKey))
        var core = try XCTUnwrap(JSONSerialization.jsonObject(with: storedCore) as? [String: Any])
        var spaces = try XCTUnwrap(core["spaces"] as? [[String: Any]])
        core["selectedSpaceID"] = try json(space.id)
        spaces[1]["selectedTabID"] = try json(tab.id)
        core["spaces"] = spaces
        defaults.set(try JSONSerialization.data(withJSONObject: core), forKey: BrowserLegacySessionDefaults.coreKey)
        // A window record written before windows remembered their Spaces.
        let recorded = BrowserWindowID()
        let record: [String: Any] = [
            "id": ["rawValue": recorded.uuidString],
            "selectedSpaceID": ["rawValue": space.id.uuidString],
            "selectedTabIDsBySpace": [Any](),
            "sidebarWidth": 289.0,
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: [record]), forKey: BrowserWindowLayouts.legacyRecordsKey)

        let crest = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let stored = try BrowserStore.migratedStorage(
            core: crest, legacy: BrowserLegacySessionDefaults(defaults: defaults, journalDefaults: [defaults]),
            favicons: icons, seed: .freshInstallSeed, environment: .current)
        XCTAssertEqual(stored.projection, installed)
        let store = BrowserStore.production(
            stored: stored, core: crest, favicons: icons, credentialVault: InMemoryCredentialVault())
        XCTAssertEqual(store.selectedSpaceID, installed.defaultSpaceID)
        XCTAssertEqual(store.selectedTabID(in: space.id), tab.id)

        let layouts = BrowserWindowLayouts(defaults: defaults)
        layouts.adoptLegacyRecords(into: crest)
        XCTAssertEqual(layouts.layout(for: recorded)?.sidebarWidth, 289)
        let window = store.makeWindowStore(BrowserWindowOpening(id: recorded, saved: true))
        XCTAssertEqual(window.selectedSpaceID, space.id)
        XCTAssertEqual(window.selectedTabID(in: space.id), tab.id)

        await store.flushPendingSyncPersistence()
        let relaunched = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let reopened = try BrowserCoreSessionAuthority.openStored(in: relaunched, favicons: icons)
        XCTAssertEqual(reopened.projection, store.session)
        let next = BrowserStore.production(
            stored: reopened, core: relaunched, favicons: icons, credentialVault: InMemoryCredentialVault())
        XCTAssertNil(next.selectedTabID(in: space.id), "The next save must not write the selection back")
    }

    /// Tab images stay native assets beside the core's file: the icon a page
    /// reports moves to its tab when the core records it and reaches the
    /// favicon store, a relaunch reattaches it, and a deleted tab's image is
    /// pruned.
    func testTabImagesFollowTheSessionIntoTheFaviconStore() async throws {
        let harness = try BrowserStoredSessionHarness(session: .preview)
        let store = harness.store
        harness.core.engines.register(WebKitEngineBinding(), isDefault: true)
        let spaceID = try XCTUnwrap(store.selectedSpace?.id)
        let tab = try XCTUnwrap(store.selectedSpace?.tabs.first { $0.url != nil && $0.iconMode.followsPage })
        let icon = Data("captured".utf8)
        let page = try XCTUnwrap(store.openReportingPage(for: tab.id, in: spaceID))
        store.finishNavigation(of: page, to: try XCTUnwrap(tab.url), titled: tab.title, icon: icon)
        XCTAssertEqual(store.session.space(id: spaceID)?.tabs.first { $0.id == tab.id }?.faviconData, icon)
        XCTAssertEqual(harness.favicons.favicon(tabID: tab.id), icon)
        XCTAssertNil(harness.core.engines.takeIcon(of: page.id), "The image moved to the tab")
        page.release(keepingState: false)
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

    /// The tab the core would show first in `space`, as a window's tabs.
    private func fallbackTabs(_ space: BrowserSpace) -> [SpaceID: TabID] {
        CrestCore().fallbackTabID(in: space).map { [space.id: $0] } ?? [:]
    }

    private func visit(_ address: String, title: String) -> BrowserHistoryEntry {
        BrowserHistoryEntry(url: URL(string: address)!, title: title, firstVisitedAt: .now, lastVisitedAt: .now)
    }
}
