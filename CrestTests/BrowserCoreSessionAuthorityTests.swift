#if CREST_CORE_BACKED
import Foundation
import XCTest
@testable import Crest

@MainActor
final class BrowserCoreSessionAuthorityTests: XCTestCase {
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
