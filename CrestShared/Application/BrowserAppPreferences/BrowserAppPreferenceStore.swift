import Foundation
import Observation

/// The Swift projection of the core's app-wide behavior preferences.
///
/// Once bound to the persistent store, every value reads the core's accepted
/// record and every edit is a `preferences.*` command; an edit the core refuses
/// or cannot answer leaves the current value in place. Before binding, and in
/// previews and tests that never bind, the store holds its own values.
@Observable
@MainActor
final class BrowserAppPreferenceStore {
    // MARK: - Variables

    static let shared = BrowserAppPreferenceStore()

    private var browser: BrowserStore?
    /// The unbound value, and the bound fallback while the session has no
    /// record because the legacy import could not commit.
    private var detached: BrowserAppPreferences

    var preferences: BrowserAppPreferences {
        browser?.family.authoritativeSession.appPreferences ?? detached
    }

    var startupBehavior: BrowserStartupBehavior {
        get { preferences.startupBehavior }
        set { set(.startupBehavior, to: .term(newValue.rawValue)) { $0.startupBehavior = newValue } }
    }

    var offersTranslation: Bool {
        get { preferences.offersTranslation }
        set { set(.offersTranslation, to: .flag(newValue)) { $0.offersTranslation = newValue } }
    }

    var automaticallyTranslates: Bool {
        get { preferences.automaticallyTranslates }
        set { set(.automaticallyTranslates, to: .flag(newValue)) { $0.automaticallyTranslates = newValue } }
    }

    var checksSpelling: Bool {
        get { preferences.checksSpelling }
        set { set(.checksSpelling, to: .flag(newValue)) { $0.checksSpelling = newValue } }
    }

    var automaticallyEntersPictureInPicture: Bool {
        get { preferences.automaticallyEntersPictureInPicture }
        set {
            set(.automaticallyEntersPictureInPicture, to: .flag(newValue)) {
                $0.automaticallyEntersPictureInPicture = newValue
            }
        }
    }

    var savedTabClosePolicy: BrowserDurableTabClosePolicy {
        get { preferences.savedTabClosePolicy }
        set { set(.savedTabClosePolicy, to: .term(newValue.rawValue)) { $0.savedTabClosePolicy = newValue } }
    }

    var returnsToSavedURLOnFaviconClick: Bool {
        get { preferences.savedTabFaviconReturnsToSavedURL }
        set {
            set(.savedTabFaviconReturnsToSavedURL, to: .flag(newValue)) {
                $0.savedTabFaviconReturnsToSavedURL = newValue
            }
        }
    }

    var splitFocusFollowsMouse: Bool {
        get { preferences.splitFocusFollowsMouse }
        set { set(.splitFocusFollowsMouse, to: .flag(newValue)) { $0.splitFocusFollowsMouse = newValue } }
    }

    // MARK: - Initializers

    init(preferences: BrowserAppPreferences = .defaults) {
        detached = preferences
    }

    // MARK: - Actions - Binding

    /// Binds the projection to the persistent store and, the first time a
    /// session has no record, imports the values the settings stored before
    /// the core owned them. Later launches find the record and import nothing.
    func bind(to browser: BrowserStore, legacy: BrowserLegacyAppPreferences) {
        detached = legacy.preferences
        self.browser = browser
        guard browser.family.authoritativeSession.appPreferences == nil else { return }
        browser.applyAppPreferenceCommand(.importing(legacy))
    }

    // MARK: - Actions - Translation

    /// Records a source language's choice through the core's alias rules. An
    /// unbound store has no core to apply them and keeps its rules.
    func setTranslationRule(sourceID: String, targetID: String, isEnabled: Bool) {
        browser?.applyAppPreferenceCommand(
            .translationRule(sourceID: sourceID, targetID: targetID, isEnabled: isEnabled))
    }

    // MARK: - Actions - Commands

    private func set(
        _ preference: BrowserAppPreference,
        to value: BrowserAppPreferenceRequest.Value,
        detached edit: (inout BrowserAppPreferences) -> Void
    ) {
        guard let browser else {
            edit(&detached)
            return
        }
        browser.applyAppPreferenceCommand(.set(preference, to: value))
    }
}
