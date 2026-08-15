protocol BrowserWindowTransparencyPersisting {
    func load() -> BrowserWindowTransparencyPreference
    func saveIsEnabled(_ isEnabled: Bool)
    func saveStrength(_ strength: Double)
}
