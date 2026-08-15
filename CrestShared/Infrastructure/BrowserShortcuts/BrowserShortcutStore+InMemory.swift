extension BrowserShortcutStore {
    static func inMemory(
        overrides: [String: BrowserShortcutOverride] = [:]
    ) -> BrowserShortcutStore {
        BrowserShortcutStore(
            persistence: InMemoryBrowserShortcutPersistence(
                overrides: overrides.isEmpty ? nil : overrides
            )
        )
    }
}
