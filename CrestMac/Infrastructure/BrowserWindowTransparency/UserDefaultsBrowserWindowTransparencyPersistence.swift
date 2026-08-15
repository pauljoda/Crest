import Foundation

struct UserDefaultsBrowserWindowTransparencyPersistence:
    BrowserWindowTransparencyPersisting
{
    static let enabledKey = "crest.appearance.window-transparency-enabled"
    static let strengthKey = "crest.appearance.window-transparency-strength"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> BrowserWindowTransparencyPreference {
        let isEnabled =
            if defaults.object(forKey: Self.enabledKey) == nil {
                BrowserWindowTransparencyPolicy.defaultEnabled
            } else {
                defaults.bool(forKey: Self.enabledKey)
            }
        let strength =
            if defaults.object(forKey: Self.strengthKey) == nil {
                BrowserWindowTransparencyPolicy.defaultStrength
            } else {
                BrowserWindowTransparencyPolicy.normalizedStrength(
                    defaults.double(forKey: Self.strengthKey)
                )
            }
        return BrowserWindowTransparencyPreference(
            isEnabled: isEnabled,
            strength: strength
        )
    }

    func saveIsEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.enabledKey)
    }

    func saveStrength(_ strength: Double) {
        defaults.set(
            BrowserWindowTransparencyPolicy.normalizedStrength(strength),
            forKey: Self.strengthKey
        )
    }
}
