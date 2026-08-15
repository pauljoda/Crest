import XCTest

@testable import Crest

@MainActor
final class BrowserShortcutCompositionTests: XCTestCase {
    func testIsolatedLaunchDoesNotConstructOrUsePersistentPersistence() {
        let persistence = PersistenceSpy()
        var persistentFactoryCallCount = 0
        let store = BrowserShortcutStore.launch(
            usesIsolatedLaunch: true,
            reset: true,
            persistentPersistence: {
                persistentFactoryCallCount += 1
                return persistence
            }
        )

        XCTAssertEqual(persistentFactoryCallCount, 0)
        XCTAssertEqual(
            store.assign(
                BrowserShortcut(
                    key: .character("g"),
                    modifiers: [.command]
                ),
                to: .newTab
            ),
            .assigned
        )
        XCTAssertEqual(persistence.loadCount, 0)
        XCTAssertEqual(persistence.saveCount, 0)
        XCTAssertEqual(persistence.removeCount, 0)
    }

    func testStandardLaunchUsesTheInjectedPersistentPersistence() {
        let persistence = PersistenceSpy()
        _ = BrowserShortcutStore.launch(
            usesIsolatedLaunch: false,
            reset: true,
            persistentPersistence: { persistence }
        )

        XCTAssertEqual(persistence.loadCount, 1)
        XCTAssertEqual(persistence.removeCount, 1)
    }

    private final class PersistenceSpy: BrowserShortcutPersisting {
        private(set) var loadCount = 0
        private(set) var saveCount = 0
        private(set) var removeCount = 0

        func load() -> [String: BrowserShortcutOverride]? {
            loadCount += 1
            return nil
        }

        func save(_ overrides: [String: BrowserShortcutOverride]) {
            saveCount += 1
        }

        func remove() {
            removeCount += 1
        }
    }
}
