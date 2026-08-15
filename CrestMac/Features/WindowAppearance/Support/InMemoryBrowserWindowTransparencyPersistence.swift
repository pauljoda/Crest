final class InMemoryBrowserWindowTransparencyPersistence:
    BrowserWindowTransparencyPersisting
{
    private(set) var preference: BrowserWindowTransparencyPreference

    init(
        preference: BrowserWindowTransparencyPreference =
            BrowserWindowTransparencyPolicy.defaultPreference
    ) {
        self.preference = preference
    }

    func load() -> BrowserWindowTransparencyPreference {
        preference
    }

    func saveIsEnabled(_ isEnabled: Bool) {
        preference.isEnabled = isEnabled
    }

    func saveStrength(_ strength: Double) {
        preference.strength = strength
    }
}
