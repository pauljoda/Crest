import Foundation

/// The behavior preferences as the settings stored them in defaults before the
/// core owned them. They are read once, when a session first has no preference
/// record, and imported through the core's `ImportAppPreferences`. The keys
/// stay in place, so an older build still finds its settings.
///
/// Each value is read from the same defaults its setting used: an isolated
/// launch never read the installed startup or Split View choices, and named
/// isolated profiles kept translation and saved-tab choices in their own suite.
/// A value that was never saved is nil.
struct BrowserLegacyAppPreferences: Equatable, Sendable {
    // MARK: - Static Variables

    static let startupKey = "crest.startup.behavior"
    static let automaticTranslationKey = "crest.translation.automaticallyTranslate"
    static let translationRulesKey = "crest.translation.languageRules"
    static let offersTranslationKey = "crest.translation.offerToTranslate"
    /// WebKit's own continuous-spelling default, which the setting wrote directly.
    static let spellCheckingKey = "WebContinuousSpellCheckingEnabled"
    static let pictureInPictureKey = "automaticallyEnterPictureInPicture"
    static let savedTabCloseKey = "crest.tabs.durable.closePolicy"
    static let savedTabFaviconKey = "crest.tabs.saved.returnToRootOnFaviconClick"
    static let splitFocusKey = "crest.split-view.focus-follows-mouse"

    // MARK: - Variables

    var startupBehavior: String?
    var offersTranslation: Bool?
    var automaticallyTranslates: Bool?
    var translationRules: String?
    var checksSpelling: Bool?
    var automaticallyEntersPictureInPicture: Bool?
    var savedTabClosePolicy: String?
    var savedTabFaviconReturnsToSavedURL: Bool?
    var splitFocusFollowsMouse: Bool?

    /// The same values read locally, which the projection keeps showing if the
    /// import cannot commit.
    var preferences: BrowserAppPreferences {
        var value = BrowserAppPreferences.defaults
        if let startup = startupBehavior.flatMap(BrowserStartupBehavior.init(rawValue:)) {
            value.startupBehavior = startup
        }
        if let offersTranslation { value.offersTranslation = offersTranslation }
        if let automaticallyTranslates { value.automaticallyTranslates = automaticallyTranslates }
        if let translationRules {
            value.translationRules = BrowserAutomaticTranslationRules(rawValue: translationRules)
        }
        if let checksSpelling { value.checksSpelling = checksSpelling }
        if let automaticallyEntersPictureInPicture {
            value.automaticallyEntersPictureInPicture = automaticallyEntersPictureInPicture
        }
        if let policy = savedTabClosePolicy.flatMap(BrowserDurableTabClosePolicy.init(rawValue:)) {
            value.savedTabClosePolicy = policy
        }
        if let savedTabFaviconReturnsToSavedURL {
            value.savedTabFaviconReturnsToSavedURL = savedTabFaviconReturnsToSavedURL
        }
        if let splitFocusFollowsMouse { value.splitFocusFollowsMouse = splitFocusFollowsMouse }
        return value
    }

    /// These values as the core's import reads them.
    var core: LegacyAppPreferences {
        LegacyAppPreferences(
            startupBehavior: startupBehavior, offersTranslation: offersTranslation,
            automaticallyTranslates: automaticallyTranslates, translationRules: translationRules,
            checksSpelling: checksSpelling, automaticallyEntersPictureInPicture: automaticallyEntersPictureInPicture,
            savedTabClosePolicy: savedTabClosePolicy,
            savedTabFaviconReturnsToSavedURL: savedTabFaviconReturnsToSavedURL,
            splitFocusFollowsMouse: splitFocusFollowsMouse)
    }

    // MARK: - Actions - Reading

    static func read(
        for environment: BrowserLaunchEnvironment,
        standard: UserDefaults = .standard
    ) -> BrowserLegacyAppPreferences {
        let installed: UserDefaults? = environment.requiresIsolation ? nil : standard
        let profile: UserDefaults? =
            environment.requiresIsolation
            ? environment.persistentIsolationID.flatMap {
                UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: $0))
            }
            : standard
        return BrowserLegacyAppPreferences(
            startupBehavior: installed?.string(forKey: startupKey),
            offersTranslation: profile?.object(forKey: offersTranslationKey) as? Bool,
            automaticallyTranslates: profile?.object(forKey: automaticTranslationKey) as? Bool,
            translationRules: profile?.string(forKey: translationRulesKey),
            checksSpelling: standard.object(forKey: spellCheckingKey) as? Bool,
            automaticallyEntersPictureInPicture: standard.object(forKey: pictureInPictureKey) as? Bool,
            savedTabClosePolicy: profile?.string(forKey: savedTabCloseKey),
            savedTabFaviconReturnsToSavedURL: profile?.object(forKey: savedTabFaviconKey) as? Bool,
            splitFocusFollowsMouse: installed?.object(forKey: splitFocusKey) as? Bool
        )
    }
}
