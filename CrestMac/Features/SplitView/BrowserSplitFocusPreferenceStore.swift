import Foundation
import Observation

/// The app-wide Split View focus preference, saved the moment it changes.
///
/// Production uses standard defaults. Isolated launches, previews, and tests
/// use their own suite so they cannot mutate the installed profile.
@Observable
@MainActor
final class BrowserSplitFocusPreferenceStore {
    static let followsMouseKey = "crest.split-view.focus-follows-mouse"

    private let defaults: UserDefaults

    var followsMouse: Bool {
        didSet {
            guard followsMouse != oldValue else { return }
            defaults.set(followsMouse, forKey: Self.followsMouseKey)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        initialFollowsMouse: Bool? = nil
    ) {
        self.defaults = defaults
        followsMouse =
            initialFollowsMouse
            ?? defaults.bool(forKey: Self.followsMouseKey)
    }

    static func launch(
        usesIsolatedLaunch: Bool,
        persistentDefaults: UserDefaults = .standard
    ) -> BrowserSplitFocusPreferenceStore {
        guard usesIsolatedLaunch else {
            return BrowserSplitFocusPreferenceStore(
                defaults: persistentDefaults
            )
        }
        return isolated()
    }

    static func isolated(
        followsMouse: Bool = false
    ) -> BrowserSplitFocusPreferenceStore {
        let suiteName =
            "crest.split-view.isolated.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated Split View defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return BrowserSplitFocusPreferenceStore(
            defaults: defaults,
            initialFollowsMouse: followsMouse
        )
    }
}
