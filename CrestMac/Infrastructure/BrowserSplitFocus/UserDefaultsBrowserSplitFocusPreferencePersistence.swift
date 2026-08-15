import Foundation

struct UserDefaultsBrowserSplitFocusPreferencePersistence:
    BrowserSplitFocusPreferencePersisting
{
    static let followsMouseKey = "crest.split-view.focus-follows-mouse"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// An absent key reads as `false`, which is also the shipped default, so no
    /// separate "has never been set" branch is needed here.
    func load() -> BrowserSplitFocusPreference {
        BrowserSplitFocusPreference(
            followsMouse: defaults.bool(forKey: Self.followsMouseKey)
        )
    }

    func saveFollowsMouse(_ followsMouse: Bool) {
        defaults.set(followsMouse, forKey: Self.followsMouseKey)
    }
}
