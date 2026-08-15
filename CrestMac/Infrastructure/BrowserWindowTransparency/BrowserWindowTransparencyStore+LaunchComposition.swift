extension BrowserWindowTransparencyStore {
    static func launch(
        usesIsolatedLaunch: Bool,
        makePersistentPersistence: () -> any BrowserWindowTransparencyPersisting = {
            UserDefaultsBrowserWindowTransparencyPersistence()
        },
        makeIsolatedPersistence: () -> any BrowserWindowTransparencyPersisting = {
            InMemoryBrowserWindowTransparencyPersistence()
        }
    ) -> BrowserWindowTransparencyStore {
        BrowserWindowTransparencyStore(
            persistence: usesIsolatedLaunch
                ? makeIsolatedPersistence()
                : makePersistentPersistence()
        )
    }
}
