import XCTest

@testable import Crest

@MainActor
final class BrowserWindowTransparencyTests: XCTestCase {
    func testUserDefaultsPersistencePreservesKeysDefaultsAndClamping() {
        let suiteName =
            "BrowserWindowTransparencyTests.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserWindowTransparencyPersistence(
            defaults: defaults
        )

        XCTAssertEqual(
            persistence.load(),
            BrowserWindowTransparencyPolicy.defaultPreference
        )
        persistence.saveIsEnabled(false)
        persistence.saveStrength(2.5)

        XCTAssertFalse(
            defaults.bool(
                forKey: UserDefaultsBrowserWindowTransparencyPersistence.enabledKey
            )
        )
        XCTAssertEqual(
            defaults.double(
                forKey: UserDefaultsBrowserWindowTransparencyPersistence.strengthKey
            ),
            BrowserWindowTransparencyPolicy.strengthRange.upperBound
        )
        XCTAssertEqual(
            persistence.load().strength,
            BrowserWindowTransparencyPolicy.strengthRange.upperBound
        )
    }

    func testStorePersistsLiveChangesThroughItsInjectedPort() {
        let persistence = InMemoryBrowserWindowTransparencyPersistence()
        let store = BrowserWindowTransparencyStore(persistence: persistence)

        store.isEnabled = false
        store.strength = 2.5

        XCTAssertEqual(
            persistence.preference,
            BrowserWindowTransparencyPreference(
                isEnabled: false,
                strength: BrowserWindowTransparencyPolicy.strengthRange.upperBound
            )
        )
    }

    func testIsolatedLaunchNeverConstructsPersistentPreferences() {
        var persistentFactoryWasCalled = false
        let store = BrowserWindowTransparencyStore.launch(
            usesIsolatedLaunch: true,
            makePersistentPersistence: {
                persistentFactoryWasCalled = true
                return InMemoryBrowserWindowTransparencyPersistence()
            },
            makeIsolatedPersistence: {
                InMemoryBrowserWindowTransparencyPersistence(
                    preference: BrowserWindowTransparencyPreference(
                        isEnabled: false,
                        strength: 0.1
                    )
                )
            }
        )

        XCTAssertFalse(persistentFactoryWasCalled)
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.strength, 0.1)
    }

    func testOpacityPolicyTracksFocusAndClampsStrength() {
        XCTAssertEqual(
            BrowserWindowTransparencyPolicy.baseLayerOpacity(
                isEnabled: true,
                strength: 0.2,
                isWindowFocused: true
            ),
            0.8
        )
        XCTAssertEqual(
            BrowserWindowTransparencyPolicy.baseLayerOpacity(
                isEnabled: true,
                strength: 0.2,
                isWindowFocused: false
            ),
            1
        )
        XCTAssertEqual(
            BrowserWindowTransparencyPolicy.baseLayerOpacity(
                isEnabled: false,
                strength: 0.2,
                isWindowFocused: true
            ),
            1
        )
        XCTAssertEqual(
            BrowserWindowTransparencyPolicy.backdropMaterialOpacity(
                isEnabled: true,
                isWindowFocused: true
            ),
            1
        )
    }
}
