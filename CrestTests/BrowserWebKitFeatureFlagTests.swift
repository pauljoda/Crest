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

    func testAllow120FPSDefaultsOnWithoutChangingScrollAnimator() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(
            features: [.preferNear60FPS, .scrollAnimator]
        )
        let persistence = InMemoryBrowserWebKitFeatureFlagPersistence()
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )

        XCTAssertTrue(store.allows120FPS)
        XCTAssertNil(store.override(for: .scrollAnimator))
        XCTAssertFalse(store.hasOverrides)
        XCTAssertEqual(store.activeOverrideCount, 0)

        store.apply(to: WKPreferences())

        XCTAssertEqual(
            registry.appliedOverrides,
            [
                BrowserWebKitFeatureFlagStore
                    .preferPageRenderingUpdatesNear60FPSKey: .disabled
            ]
        )
    }

    func testAllow120FPSSettingPersistsAndStaysInSyncWithRawOverride() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(
            features: [.preferNear60FPS, .scrollAnimator]
        )
        let persistence = InMemoryBrowserWebKitFeatureFlagPersistence()
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )

        store.allows120FPS = false

        XCTAssertFalse(store.allows120FPS)
        XCTAssertEqual(store.activeOverrideCount, 1)
        XCTAssertEqual(
            persistence.overrides,
            [
                BrowserWebKitFeatureFlagStore
                    .preferPageRenderingUpdatesNear60FPSKey: .enabled
            ]
        )

        store.setOverride(.disabled, for: .preferNear60FPS)

        XCTAssertTrue(store.allows120FPS)
        XCTAssertFalse(store.hasOverrides)

        store.setOverride(nil, for: .preferNear60FPS)

        XCTAssertTrue(store.allows120FPS)
    }

    func testScrollAnimatorRemainsAnOrdinaryRawFeatureFlag() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(
            features: [.preferNear60FPS, .scrollAnimator]
        )
        let persistence = InMemoryBrowserWebKitFeatureFlagPersistence()
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )

        XCTAssertNil(store.override(for: .scrollAnimator))

        store.setOverride(.enabled, for: .scrollAnimator)

        XCTAssertEqual(store.override(for: .scrollAnimator), .enabled)
        XCTAssertEqual(store.activeOverrideCount, 1)
        XCTAssertEqual(
            persistence.overrides,
            [
                BrowserWebKitFeatureFlagStore
                    .preferPageRenderingUpdatesNear60FPSKey: .disabled,
                BrowserWebKitFeatureFlag.scrollAnimator.key: .enabled,
            ]
        )

        store.setOverride(nil, for: .scrollAnimator)

        XCTAssertNil(store.override(for: .scrollAnimator))
        XCTAssertEqual(store.activeOverrideCount, 0)
    }

    func testResetAllRestoresCrestPerformanceDefaults() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(
            features: [.preferNear60FPS, .scrollAnimator, .preview]
        )
        let persistence = InMemoryBrowserWebKitFeatureFlagPersistence(
            overrides: [
                BrowserWebKitFeatureFlagStore
                    .preferPageRenderingUpdatesNear60FPSKey: .enabled,
                BrowserWebKitFeatureFlag.scrollAnimator.key: .disabled,
                BrowserWebKitFeatureFlag.preview.key: .enabled,
            ]
        )
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )

        store.resetAll()

        XCTAssertTrue(store.allows120FPS)
        XCTAssertNil(store.override(for: .scrollAnimator))
        XCTAssertFalse(store.hasOverrides)
        XCTAssertEqual(
            persistence.overrides,
            [
                BrowserWebKitFeatureFlagStore
                    .preferPageRenderingUpdatesNear60FPSKey: .disabled
            ]
        )
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

    fileprivate static let preferNear60FPS = BrowserWebKitFeatureFlag(
        key: BrowserWebKitFeatureFlagStore
            .preferPageRenderingUpdatesNear60FPSKey,
        name: "Prefer Page Rendering Updates Near 60 FPS",
        details: "Prefer page rendering updates near 60 FPS",
        status: BrowserWebKitFeatureStatus(rawValue: 6),
        category: BrowserWebKitFeatureCategory(rawValue: 3),
        defaultValue: true
    )

    fileprivate static let scrollAnimator = BrowserWebKitFeatureFlag(
        key: "ScrollAnimatorEnabled",
        name: "Scroll Animator",
        details: "Use the WebKit scroll animator",
        status: BrowserWebKitFeatureStatus(rawValue: 6),
        category: BrowserWebKitFeatureCategory(rawValue: 3),
        defaultValue: false
    )
}
