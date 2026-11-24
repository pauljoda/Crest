import Foundation

protocol BrowserWebKitFeatureFlagPersisting: AnyObject {
    func load() -> [String: BrowserWebKitFeatureFlagOverride]
    func save(_ overrides: [String: BrowserWebKitFeatureFlagOverride])
}

final class UserDefaultsBrowserWebKitFeatureFlagPersistence:
    BrowserWebKitFeatureFlagPersisting
{
    static let currentKey = "crest.webkit-feature-flag-overrides.v1"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = currentKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [String: BrowserWebKitFeatureFlagOverride] {
        guard let storedValues = defaults.dictionary(forKey: key) else {
            return [:]
        }
        // The 60 frames a second flag, in any slot, is the page preference
        // the core keeps; the device store carried it once.
        return storedValues.reduce(into: [:]) { result, entry in
            guard !entry.key.hasPrefix(BrowserWebKitFeatureFlagStore.preferPageRenderingUpdatesNear60FPSKey),
                let rawValue = entry.value as? String,
                let override = BrowserWebKitFeatureFlagOverride(rawValue: rawValue)
            else { return }
            result[entry.key] = override
        }
    }

    /// Saves `overrides`, keeping the frame-rate slot an earlier release
    /// wrote, so that release still finds it.
    func save(_ overrides: [String: BrowserWebKitFeatureFlagOverride]) {
        let slot = BrowserLegacyDeviceDefaults.frameRateSlot
        var storedValues: [String: Any] = overrides.mapValues(\.rawValue)
        storedValues[slot] = defaults.dictionary(forKey: key)?[slot]
        guard !storedValues.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(storedValues, forKey: key)
    }
}

final class InMemoryBrowserWebKitFeatureFlagPersistence:
    BrowserWebKitFeatureFlagPersisting
{
    private(set) var overrides: [String: BrowserWebKitFeatureFlagOverride]

    init(overrides: [String: BrowserWebKitFeatureFlagOverride] = [:]) {
        self.overrides = overrides
    }

    func load() -> [String: BrowserWebKitFeatureFlagOverride] {
        overrides
    }

    func save(_ overrides: [String: BrowserWebKitFeatureFlagOverride]) {
        self.overrides = overrides
    }
}
