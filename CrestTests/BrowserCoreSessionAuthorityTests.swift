#if CREST_CORE_BACKED
import Foundation
import XCTest
@testable import Crest

@MainActor
final class BrowserCoreSessionAuthorityTests: XCTestCase {
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
