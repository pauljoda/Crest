/// The Split View focus preference for an isolated launch, a preview, or a test:
/// held for as long as the process runs and never written anywhere.
final class InMemoryBrowserSplitFocusPreferencePersistence:
    BrowserSplitFocusPreferencePersisting
{
    private(set) var preference: BrowserSplitFocusPreference

    init(preference: BrowserSplitFocusPreference = BrowserSplitFocusPreference()) {
        self.preference = preference
    }

    func load() -> BrowserSplitFocusPreference {
        preference
    }

    func saveFollowsMouse(_ followsMouse: Bool) {
        preference.followsMouse = followsMouse
    }
}
