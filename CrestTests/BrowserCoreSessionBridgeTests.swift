import Foundation
import XCTest

@testable import Crest

/// TRANSITIONAL until S6.7 retires the Swift session copy: the copy follows
/// only the session changes the core publishes, so after any sequence of
/// commands it holds what a relaunch reads from the core's file, and applying
/// a batch again changes nothing.
@MainActor
final class BrowserCoreSessionBridgeTests: XCTestCase {
    func testTheCopyHoldsWhatARelaunchReadsAfterEveryKindOfCommand() async throws {
        var original = BrowserSession.preview
        let icon = Data([7, 7, 7])
        original.spaces[0].tabs[0].faviconData = icon
        original.spaces[0].tabs[0].faviconURL = original.spaces[0].tabs[0].url
        let harness = try BrowserStoredSessionHarness(session: original)
        let store = harness.store
        harness.core.engines.register(WebKitEngineBinding(), isDefault: true)
        var batches: [[Change]] = []
        harness.core.batchApplied = { batches.append($0) }
        let spaceID = original.spaces[0].id
        store.selectSpace(spaceID)

        let opened = try XCTUnwrap(
            store.openSessionTab(.page(URL(string: "https://opened.example/")!, title: "Opened"), in: spaceID))
        XCTAssertTrue(store.setTabCustomTitle("Renamed", for: opened, in: spaceID))
        let page = try XCTUnwrap(store.openReportingPage(for: nil, in: spaceID))
        store.finishNavigation(of: page, to: try XCTUnwrap(URL(string: "https://visited.example/a")), titled: "First")
        store.finishNavigation(
            of: page, to: try XCTUnwrap(URL(string: "https://visited.example/a#again")), titled: "Again")
        XCTAssertTrue(store.closeTab(opened, in: spaceID))
        store.restoreArchivedTab(opened)
        let folder = try XCTUnwrap(
            store.addFolder(title: "Reading", matching: BrowserSpaceRuntimeAssignment(space: store.session.spaces[0])))
        store.selectTab(original.spaces[0].tabs[0].id)
        store.updateSpaceIdentity(spaceID, name: "Renamed Space", symbol: "book", accent: .teal)
        store.addSpace()

        let session = store.session
        let space = try XCTUnwrap(session.space(id: spaceID))
        XCTAssertEqual(space.name, "Renamed Space")
        XCTAssertEqual(space.accent, .teal)
        XCTAssertTrue(space.folders.contains { $0.id == folder })
        XCTAssertEqual(space.tabs.first { $0.id == opened }?.customTitle, "Renamed")
        XCTAssertEqual(space.history.first?.visitCount, 2)
        XCTAssertEqual(space.tabs.first { $0.id == original.spaces[0].tabs[0].id }?.faviconData, icon)
        XCTAssertEqual(session.spaces.count, original.spaces.count + 1)
        XCTAssertFalse(batches.isEmpty)

        // Every change is idempotent: the copy holds the same session after
        // each batch is applied again.
        for batch in batches {
            for change in batch { harness.core.state.apply(change) }
            harness.core.state.finishBatch(batch)
        }
        XCTAssertEqual(store.session, session)

        let relaunched = try await harness.relaunch()
        XCTAssertEqual(relaunched.store.session, session)
    }

    /// A merge from another device commits as one durable replacement, and the
    /// copy follows it through the core's changes: the remote rename and the
    /// tab the other device saved, with the images local tabs wear kept.
    func testAMergeFromAnotherDeviceReachesTheCopy() async throws {
        var original = BrowserSession.preview
        let icon = Data([9, 9, 9])
        original.spaces[0].tabs[0].faviconData = icon
        original.spaces[0].tabs[0].faviconURL = original.spaces[0].tabs[0].url
        var journal = BrowserSyncJournal()
        try journal.stage(session: original)
        let harness = try BrowserStoredSessionHarness(session: original, journal: journal)
        let store = harness.store
        let other = store.makeWindowStore()

        var remote = store.session
        remote.spaces[0].name = "Named elsewhere"
        let added = BrowserTab(
            title: "From elsewhere", url: URL(string: "https://elsewhere.example/"), placement: .saved)
        remote.spaces[0].tabs.append(added)
        // Another device that holds every record this one staged edits it.
        var remoteJournal = BrowserSyncJournal()
        try remoteJournal.merge(try XCTUnwrap(store.syncCoordinator).journal.records)
        try remoteJournal.stage(session: remote)
        try store.mergeRemoteSyncRecords(remoteJournal.records)

        let merged = try XCTUnwrap(store.session.space(id: original.spaces[0].id))
        XCTAssertEqual(merged.name, "Named elsewhere")
        XCTAssertTrue(merged.tabs.contains { $0.id == added.id })
        XCTAssertEqual(merged.tabs.first { $0.id == original.spaces[0].tabs[0].id }?.faviconData, icon)
        XCTAssertEqual(other.session, store.session)
        XCTAssertEqual(try harness.stored().session, store.session)
        let relaunched = try await harness.relaunch()
        XCTAssertEqual(relaunched.store.session, store.session)
    }
}
