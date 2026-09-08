extension BrowserShortcutStore {
    static func launch(
        usesIsolatedLaunch: Bool,
        reset: Bool,
        persistentPersistence: () -> any BrowserShortcutPersisting = {
            UserDefaultsBrowserShortcutPersistence(defaults: .standard)
        }
    ) -> BrowserShortcutStore {
        guard !usesIsolatedLaunch else {
            return .inMemory()
        }
        return BrowserShortcutStore(
            persistence: persistentPersistence(),
            reset: reset
        )
    }
}
