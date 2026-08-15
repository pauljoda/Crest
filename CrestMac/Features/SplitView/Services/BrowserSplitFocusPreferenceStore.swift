import Observation

/// The app-wide Split View focus preference, saved the moment it changes.
///
/// One store for the whole app rather than one per window: focus behaviour is how
/// someone works, not a property of a particular window, and a second window that
/// disagreed with the first would be a bug nobody could explain.
@Observable
@MainActor
final class BrowserSplitFocusPreferenceStore {
    private let persistence: any BrowserSplitFocusPreferencePersisting

    var followsMouse: Bool {
        didSet {
            guard followsMouse != oldValue else { return }
            persistence.saveFollowsMouse(followsMouse)
        }
    }

    init(persistence: any BrowserSplitFocusPreferencePersisting) {
        self.persistence = persistence
        followsMouse = persistence.load().followsMouse
    }
}
