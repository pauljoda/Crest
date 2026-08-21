import Observation
import WebKit

@MainActor
@Observable
final class BrowserWebKitFeatureFlagStore {
    static private(set) var active = BrowserWebKitFeatureFlagStore(
        registry: BrowserWebKitFeatureFlagRegistry(),
        persistence: InMemoryBrowserWebKitFeatureFlagPersistence()
    )

    let features: [BrowserWebKitFeatureFlag]
    let availabilityFailure: String?

    private(set) var overrides: [String: BrowserWebKitFeatureFlagOverride]
    private(set) var requiresRestart = false

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
        overrides = persistence.load()
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
        !overrides.isEmpty
    }

    var activeOverrideCount: Int {
        let availableKeys = Set(features.map(\.key))
        return overrides.keys.lazy.filter(availableKeys.contains).count
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
        guard overrides[flag.key] != override else { return }
        overrides[flag.key] = override
        persistChange()
    }

    func resetAll() {
        guard !overrides.isEmpty else { return }
        overrides = [:]
        persistChange()
    }

    func apply(to preferences: WKPreferences) {
        registry.apply(overrides, to: preferences)
    }

    private func persistChange() {
        persistence.save(overrides)
        requiresRestart = true
    }
}
