extension BrowserSplitFocusPreferenceStore {
    /// An isolated launch never constructs the persistent adapter, so a fixture
    /// or validation launch can toggle the preference without touching the
    /// installed app's defaults.
    static func launch(
        usesIsolatedLaunch: Bool,
        makePersistentPersistence: () -> any BrowserSplitFocusPreferencePersisting = {
            UserDefaultsBrowserSplitFocusPreferencePersistence()
        },
        makeIsolatedPersistence: () -> any BrowserSplitFocusPreferencePersisting = {
            InMemoryBrowserSplitFocusPreferencePersistence()
        }
    ) -> BrowserSplitFocusPreferenceStore {
        BrowserSplitFocusPreferenceStore(
            persistence: usesIsolatedLaunch
                ? makeIsolatedPersistence()
                : makePersistentPersistence()
        )
    }
}
