@MainActor
enum BrowserWindowTransparencyPreviewFixture {
    static func makeStore(
        isEnabled: Bool = true,
        strength: Double = BrowserWindowTransparencyPolicy.defaultStrength
    ) -> BrowserWindowTransparencyStore {
        BrowserWindowTransparencyStore(
            persistence: InMemoryBrowserWindowTransparencyPersistence(
                preference: BrowserWindowTransparencyPreference(
                    isEnabled: isEnabled,
                    strength: strength
                )
            )
        )
    }
}
