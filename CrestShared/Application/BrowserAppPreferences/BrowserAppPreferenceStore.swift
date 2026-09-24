import Foundation
import Observation

/// The Swift projection of the core's app-wide behavior preferences.
///
/// Once bound to the persistent store, every value reads the core's accepted
/// record and every edit is an intent that sets the whole record; an edit the
/// core refuses leaves the current value in place. Before binding, and in
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
        set { set { $0.startupBehavior = newValue } }
    }

    var offersTranslation: Bool {
        get { preferences.offersTranslation }
        set { set { $0.offersTranslation = newValue } }
    }

    var automaticallyTranslates: Bool {
        get { preferences.automaticallyTranslates }
        set { set { $0.automaticallyTranslates = newValue } }
    }

    var checksSpelling: Bool {
        get { preferences.checksSpelling }
        set { set { $0.checksSpelling = newValue } }
    }

    var automaticallyEntersPictureInPicture: Bool {
        get { preferences.automaticallyEntersPictureInPicture }
        set {
            set { $0.automaticallyEntersPictureInPicture = newValue }
        }
    }

    var savedTabClosePolicy: BrowserDurableTabClosePolicy {
        get { preferences.savedTabClosePolicy }
        set { set { $0.savedTabClosePolicy = newValue } }
    }

    var returnsToSavedURLOnFaviconClick: Bool {
        get { preferences.savedTabFaviconReturnsToSavedURL }
        set {
            set { $0.savedTabFaviconReturnsToSavedURL = newValue }
        }
    }

    var splitFocusFollowsMouse: Bool {
        get { preferences.splitFocusFollowsMouse }
        set { set { $0.splitFocusFollowsMouse = newValue } }
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
        browser.sendAppPreferences(ImportAppPreferences(workspaceID: browser.family.workspaceID, legacy: legacy.core))
    }

    // MARK: - Actions - Translation

    /// Records a source language's choice through the core's alias rules. An
    /// unbound store has no core to apply them and keeps its rules.
    func setTranslationRule(sourceID: String, targetID: String, isEnabled: Bool) {
        guard let browser else { return }
        browser.sendAppPreferences(
            SetTranslationRule(
                workspaceID: browser.family.workspaceID, sourceLanguage: sourceID, targetLanguage: targetID,
                isEnabled: isEnabled))
    }

    // MARK: - Actions - Commands

    /// Applies `edit` to the unbound value, or sends the record it makes of
    /// the current one to the core.
    private func set(_ edit: (inout BrowserAppPreferences) -> Void) {
        guard let browser else {
            edit(&detached)
            return
        }
        var next = preferences
        edit(&next)
        browser.sendAppPreferences(SetAppPreferences(workspaceID: browser.family.workspaceID, preferences: next.core))
    }
}
