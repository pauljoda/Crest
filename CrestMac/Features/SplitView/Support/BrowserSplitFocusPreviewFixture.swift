/// An in-memory Split View focus store for previews.
@MainActor
enum BrowserSplitFocusPreviewFixture {
    static func makeStore(
        followsMouse: Bool = false
    ) -> BrowserSplitFocusPreferenceStore {
        BrowserSplitFocusPreferenceStore(
            persistence: InMemoryBrowserSplitFocusPreferencePersistence(
                preference: BrowserSplitFocusPreference(
                    followsMouse: followsMouse
                )
            )
        )
    }
}
