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
        return storedValues.reduce(into: [:]) { result, entry in
            guard let rawValue = entry.value as? String,
                let override = BrowserWebKitFeatureFlagOverride(rawValue: rawValue)
            else { return }
            result[entry.key] = override
        }
    }

    func save(_ overrides: [String: BrowserWebKitFeatureFlagOverride]) {
        guard !overrides.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(
            overrides.mapValues(\.rawValue),
            forKey: key
        )
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
