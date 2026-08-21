import Observation
import WebKit

@MainActor
@Observable
final class BrowserWebKitFeatureFlagStore {
    nonisolated static let preferPageRenderingUpdatesNear60FPSKey =
        "PreferPageRenderingUpdatesNear60FPSEnabled"
    nonisolated static let scrollAnimatorKey = "ScrollAnimatorEnabled"

    private static let performanceDefaults: [String: BrowserWebKitFeatureFlagOverride] = [
        // This WebKit feature is phrased as a 60 FPS preference, so disabling
        // it lets page rendering follow a higher-refresh-rate display.
        preferPageRenderingUpdatesNear60FPSKey: .disabled,
        scrollAnimatorKey: .enabled,
    ]

    static private(set) var active = BrowserWebKitFeatureFlagStore(
        registry: BrowserWebKitFeatureFlagRegistry(),
        persistence: InMemoryBrowserWebKitFeatureFlagPersistence()
    )

    let features: [BrowserWebKitFeatureFlag]
    let availabilityFailure: String?

    private(set) var overrides: [String: BrowserWebKitFeatureFlagOverride]
    private(set) var requiresRestart = false

    @ObservationIgnored
    private let crestDefaultOverrides: [String: BrowserWebKitFeatureFlagOverride]

    @ObservationIgnored
    private let registry: any BrowserWebKitFeatureFlagRegistryProviding
    @ObservationIgnored
    private let persistence: any BrowserWebKitFeatureFlagPersisting

    init(
        registry: any BrowserWebKitFeatureFlagRegistryProviding,
        persistence: any BrowserWebKitFeatureFlagPersisting
    ) {
        self.registry = registry
        self.persistence = persistence
        features = registry.features
        availabilityFailure = registry.availabilityFailure
        let availableKeys = Set(features.map(\.key))
        crestDefaultOverrides = Self.performanceDefaults.filter {
            availableKeys.contains($0.key)
        }
        overrides = crestDefaultOverrides.merging(persistence.load()) {
            _, persistedOverride in persistedOverride
        }
    }

    static func configureForLaunch(usesIsolatedLaunch: Bool) {
        active = BrowserWebKitFeatureFlagStore(
            registry: BrowserWebKitFeatureFlagRegistry(),
            persistence: usesIsolatedLaunch
                ? InMemoryBrowserWebKitFeatureFlagPersistence()
                : UserDefaultsBrowserWebKitFeatureFlagPersistence()
        )
    }

    var hasOverrides: Bool {
        overrides != crestDefaultOverrides
    }

    var activeOverrideCount: Int {
        let availableKeys = Set(features.map(\.key))
        return overrides.lazy.filter { key, override in
            availableKeys.contains(key)
                && self.crestDefaultOverrides[key] != override
        }.count
    }

    var canConfigureAllow120FPS: Bool {
        crestDefaultOverrides[
            Self.preferPageRenderingUpdatesNear60FPSKey
        ] != nil
    }

    var canConfigureSmoothScroll: Bool {
        crestDefaultOverrides[Self.scrollAnimatorKey] != nil
    }

    var allows120FPS: Bool {
        get {
            overrides[
                Self.preferPageRenderingUpdatesNear60FPSKey
            ] == .disabled
        }
        set {
            setPerformanceOverride(
                newValue ? .disabled : .enabled,
                forKey: Self.preferPageRenderingUpdatesNear60FPSKey
            )
        }
    }

    var usesSmoothScroll: Bool {
        get { overrides[Self.scrollAnimatorKey] == .enabled }
        set {
            setPerformanceOverride(
                newValue ? .enabled : .disabled,
                forKey: Self.scrollAnimatorKey
            )
        }
    }

    var availableStatuses: [BrowserWebKitFeatureStatus] {
        Array(Set(features.map(\.status))).sorted { $0.rawValue < $1.rawValue }
    }

    var availableCategories: [BrowserWebKitFeatureCategory] {
        Array(Set(features.map(\.category))).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func override(
        for flag: BrowserWebKitFeatureFlag
    ) -> BrowserWebKitFeatureFlagOverride? {
        overrides[flag.key]
    }

    func setOverride(
        _ override: BrowserWebKitFeatureFlagOverride?,
        for flag: BrowserWebKitFeatureFlag
    ) {
        let resolvedOverride = override ?? crestDefaultOverrides[flag.key]
        guard overrides[flag.key] != resolvedOverride else { return }
        overrides[flag.key] = resolvedOverride
        persistChange()
    }

    func resetAll() {
        guard overrides != crestDefaultOverrides else { return }
        overrides = crestDefaultOverrides
        persistChange()
    }

    func apply(to preferences: WKPreferences) {
        registry.apply(overrides, to: preferences)
    }

    private func persistChange() {
        persistence.save(overrides)
        requiresRestart = true
    }

    private func setPerformanceOverride(
        _ override: BrowserWebKitFeatureFlagOverride,
        forKey key: String
    ) {
        guard
            crestDefaultOverrides[key] != nil,
            overrides[key] != override
        else {
            return
        }
        overrides[key] = override
        persistChange()
    }
}
