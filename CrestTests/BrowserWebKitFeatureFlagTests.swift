import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWebKitFeatureFlagTests: XCTestCase {
    func testSystemRegistryBuildsAVisibleRuntimeCatalogWithStableKeys() throws {
        let registry = BrowserWebKitFeatureFlagRegistry()

        XCTAssertNil(registry.availabilityFailure)
        XCTAssertGreaterThan(registry.features.count, 100)
        XCTAssertEqual(
            Set(registry.features.map(\.key)).count,
            registry.features.count
        )
        XCTAssertTrue(registry.features.allSatisfy { !$0.name.isEmpty })
    }

    func testSystemRegistryCanOverrideAndRestoreATemporaryPreferencesObject() throws {
        let registry = BrowserWebKitFeatureFlagRegistry()
        let flag = try XCTUnwrap(registry.features.first)
        let preferences = WKPreferences()
        let originalValue = try XCTUnwrap(
            registry.value(forKey: flag.key, in: preferences)
        )

        registry.apply(
            [flag.key: originalValue ? .disabled : .enabled],
            to: preferences
        )

        XCTAssertEqual(
            registry.value(forKey: flag.key, in: preferences),
            !originalValue
        )

        registry.apply(
            [flag.key: originalValue ? .enabled : .disabled],
            to: preferences
        )
        XCTAssertEqual(
            registry.value(forKey: flag.key, in: preferences),
            originalValue
        )
    }

    func testUserDefaultsPersistenceRoundTripsOverridesAndIgnoresUnknownValues() throws {
        let suiteName = "crest.tests.webkit-feature-flags.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserWebKitFeatureFlagPersistence(
            defaults: defaults
        )

        persistence.save(["EnabledFeature": .enabled, "DisabledFeature": .disabled])
        XCTAssertEqual(
            persistence.load(),
            ["EnabledFeature": .enabled, "DisabledFeature": .disabled]
        )

        defaults.set(
            ["EnabledFeature": "enabled", "OldFeature": "unexpected"],
            forKey: UserDefaultsBrowserWebKitFeatureFlagPersistence.currentKey
        )
        XCTAssertEqual(persistence.load(), ["EnabledFeature": .enabled])

        persistence.save([:])
        XCTAssertNil(
            defaults.object(
                forKey: UserDefaultsBrowserWebKitFeatureFlagPersistence.currentKey
            )
        )
    }

    func testStorePersistsTriStateChangesAndMarksTheProcessForRestart() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(
            features: [BrowserWebKitFeatureFlag.preview]
        )
        let persistence = InMemoryBrowserWebKitFeatureFlagPersistence()
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )

        XCTAssertNil(store.override(for: BrowserWebKitFeatureFlag.preview))
        XCTAssertFalse(store.requiresRestart)

        store.setOverride(.enabled, for: BrowserWebKitFeatureFlag.preview)
        XCTAssertEqual(
            store.override(for: BrowserWebKitFeatureFlag.preview),
            .enabled
        )
        XCTAssertEqual(
            persistence.overrides,
            [BrowserWebKitFeatureFlag.preview.key: .enabled]
        )
        XCTAssertTrue(store.requiresRestart)

        store.apply(to: WKPreferences())
        XCTAssertEqual(
            registry.appliedOverrides,
            [BrowserWebKitFeatureFlag.preview.key: .enabled]
        )
        XCTAssertEqual(registry.applyCallCount, 1)

        store.setOverride(nil, for: BrowserWebKitFeatureFlag.preview)
        XCTAssertNil(store.override(for: BrowserWebKitFeatureFlag.preview))
        XCTAssertTrue(persistence.overrides.isEmpty)
    }

    func testFilterCombinesSearchStatusCategoryAndChangedState() {
        let flags: [BrowserWebKitFeatureFlag] = [
            .preview, .stable, .media,
        ]
        var filter = BrowserWebKitFeatureFlagFilter(
            searchText: "animation",
            status: BrowserWebKitFeatureStatus(rawValue: 5),
            category: BrowserWebKitFeatureCategory(rawValue: 2),
            showsOnlyChanged: true
        )

        XCTAssertEqual(
            filter.groups(
                from: flags,
                overrides: [BrowserWebKitFeatureFlag.preview.key: .enabled]
            ).flatMap(\.flags),
            [.preview]
        )

        filter.searchText = "missing"
        XCTAssertTrue(
            filter.groups(
                from: flags,
                overrides: [BrowserWebKitFeatureFlag.preview.key: .enabled]
            ).isEmpty
        )
    }
}

@MainActor
private final class StubBrowserWebKitFeatureFlagRegistry:
    BrowserWebKitFeatureFlagRegistryProviding
{
    let features: [BrowserWebKitFeatureFlag]
    let availabilityFailure: String? = nil
    private(set) var appliedOverrides: [String: BrowserWebKitFeatureFlagOverride] = [:]
    private(set) var applyCallCount = 0

    init(features: [BrowserWebKitFeatureFlag]) {
        self.features = features
    }

    func apply(
        _ overrides: [String: BrowserWebKitFeatureFlagOverride],
        to preferences: WKPreferences
    ) {
        appliedOverrides = overrides
        applyCallCount += 1
    }
}

extension BrowserWebKitFeatureFlag {
    fileprivate static let preview = BrowserWebKitFeatureFlag(
        key: "PreviewAnimationEnabled",
        name: "Preview Animation",
        details: "Enable a preview animation feature",
        status: BrowserWebKitFeatureStatus(rawValue: 5),
        category: BrowserWebKitFeatureCategory(rawValue: 2),
        defaultValue: false
    )

    fileprivate static let stable = BrowserWebKitFeatureFlag(
        key: "StableDOMEnabled",
        name: "Stable DOM",
        details: "Enable a stable DOM feature",
        status: BrowserWebKitFeatureStatus(rawValue: 6),
        category: BrowserWebKitFeatureCategory(rawValue: 3),
        defaultValue: true
    )

    fileprivate static let media = BrowserWebKitFeatureFlag(
        key: "MediaTestingEnabled",
        name: "Media Testing",
        details: "Enable media testing",
        status: BrowserWebKitFeatureStatus(rawValue: 4),
        category: BrowserWebKitFeatureCategory(rawValue: 7),
        defaultValue: false
    )
}
