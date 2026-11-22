import Observation
import WebKit

extension BackgroundPageActivity {
    /// The activity as WebKit schedules a page out of sight.
    fileprivate var webKitValue: WKPreferences.InactiveSchedulingPolicy {
        self == .throttle ? .throttle : .suspend
    }
}

@MainActor
@Observable
final class BrowserWebKitFeatureFlagStore {
    nonisolated static let preferPageRenderingUpdatesNear60FPSKey =
        "PreferPageRenderingUpdatesNear60FPSEnabled"

    private static let performanceDefaults: [String: BrowserWebKitFeatureFlagOverride] = [
        // Prefer WebKit's usual page-rendering cadence. Native scrolling can
        // still use a higher refresh rate independently of page animation work.
        preferPageRenderingUpdatesNear60FPSKey: .enabled
    ]

    /// The store pages read their WebKit preferences from: the launch's once
    /// the launch configures it, and before that one over a memory-only core
    /// of its own, made on first use, as previews and tests use.
    static var active: BrowserWebKitFeatureFlagStore {
        if let configured { return configured }
        let store = BrowserWebKitFeatureFlagStore(
            registry: BrowserWebKitFeatureFlagRegistry(),
            persistence: InMemoryBrowserWebKitFeatureFlagPersistence(),
            core: CrestCore()
        )
        configured = store
        return store
    }

    /// The store `active` answers, once there is one.
    private static var configured: BrowserWebKitFeatureFlagStore?

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
    /// The core whose device store keeps what a page out of sight keeps doing
    /// and whether pages may draw faster than 60 frames a second.
    @ObservationIgnored
    private let core: CrestCore

    init(
        registry: any BrowserWebKitFeatureFlagRegistryProviding,
        persistence: any BrowserWebKitFeatureFlagPersisting,
        core: CrestCore
    ) {
        self.registry = registry
        self.persistence = persistence
        self.core = core
        features = registry.features
        availabilityFailure = registry.availabilityFailure
        let availableKeys = Set(features.map(\.key))
        crestDefaultOverrides = Self.performanceDefaults.filter {
            availableKeys.contains($0.key)
        }
        overrides = crestDefaultOverrides.merging(persistence.load()) {
            _, persistedOverride in persistedOverride
        }
        if crestDefaultOverrides[Self.preferPageRenderingUpdatesNear60FPSKey] != nil {
            overrides[Self.preferPageRenderingUpdatesNear60FPSKey] =
                core.state.pagePreferences.allowsHighFrameRate ? .disabled : .enabled
        }
    }

    /// The store pages read their WebKit preferences from, over the launch's
    /// `core`, which keeps the page preferences, and the flags this device
    /// overrode, which an isolated launch keeps in memory.
    static func configureForLaunch(usesIsolatedLaunch: Bool, core: CrestCore) {
        configured = BrowserWebKitFeatureFlagStore(
            registry: BrowserWebKitFeatureFlagRegistry(),
            persistence: usesIsolatedLaunch
                ? InMemoryBrowserWebKitFeatureFlagPersistence()
                : UserDefaultsBrowserWebKitFeatureFlagPersistence(),
            core: core
        )
    }

    /// What a page in a tab out of sight keeps doing, as the core keeps it.
    var backgroundActivity: BackgroundPageActivity {
        core.state.pagePreferences.backgroundActivity
    }

    /// Whether this device overrode a flag. The 60 frames a second flag is the
    /// page preference the core keeps, so it never counts.
    var hasOverrides: Bool {
        flagOverrides != crestDefaultOverrides.filter { $0.key != Self.preferPageRenderingUpdatesNear60FPSKey }
    }

    /// How many of the flags WebKit offers this device overrode, leaving out
    /// the 60 frames a second flag.
    var activeOverrideCount: Int {
        let availableKeys = Set(features.map(\.key))
        return flagOverrides.lazy.filter { key, override in
            availableKeys.contains(key)
                && self.crestDefaultOverrides[key] != override
        }.count
    }

    /// The flags this device overrode, without the 60 frames a second flag,
    /// which is the page preference the core keeps.
    private var flagOverrides: [String: BrowserWebKitFeatureFlagOverride] {
        overrides.filter { $0.key != Self.preferPageRenderingUpdatesNear60FPSKey }
    }

    var canConfigureAllow120FPS: Bool {
        crestDefaultOverrides[
            Self.preferPageRenderingUpdatesNear60FPSKey
        ] != nil
    }

    /// Whether pages may draw faster than 60 frames a second, as the core
    /// keeps it, which the store applies as WebKit's 60 frames a second flag.
    var allows120FPS: Bool {
        get { core.state.pagePreferences.allowsHighFrameRate }
        set {
            let key = Self.preferPageRenderingUpdatesNear60FPSKey
            guard canConfigureAllow120FPS, newValue != allows120FPS else { return }
            _ = try? core.send(SetHighFrameRate(allowed: newValue))
            overrides[key] = newValue ? .disabled : .enabled
            requiresRestart = true
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
        // The 60 frames a second flag is the page preference the core keeps.
        if flag.key == Self.preferPageRenderingUpdatesNear60FPSKey {
            allows120FPS = resolvedOverride == .disabled
            return
        }
        guard overrides[flag.key] != resolvedOverride else { return }
        overrides[flag.key] = resolvedOverride
        persistChange()
    }

    /// Drops every flag this device overrode, keeping the 60 frames a second
    /// flag the core's page preference sets.
    func resetAll() {
        let key = Self.preferPageRenderingUpdatesNear60FPSKey
        var reset = crestDefaultOverrides
        if reset[key] != nil { reset[key] = overrides[key] }
        guard overrides != reset else { return }
        overrides = reset
        persistChange()
    }

    func apply(to preferences: WKPreferences) {
        preferences.inactiveSchedulingPolicy = backgroundActivity.webKitValue
        registry.apply(overrides, to: preferences)
    }

    /// Keeps `activity` as what a page out of sight keeps doing, from the
    /// next page WebKit makes.
    func setBackgroundActivity(_ activity: BackgroundPageActivity) {
        guard backgroundActivity != activity else { return }
        _ = try? core.send(SetBackgroundPageActivity(activity: activity))
        requiresRestart = true
    }

    /// Saves the flags this device overrode, leaving out the 60 frames a
    /// second flag, which the core keeps as a page preference.
    private func persistChange() {
        persistence.save(flagOverrides)
        requiresRestart = true
    }
}
