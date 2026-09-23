import Foundation

/// The core's app-wide behavior preferences, as the session projection carries
/// them. The core owns the record: it lives beside the Spaces in the session
/// checkpoint, stays on this device, and changes only through `preferences.*`
/// commands. Appearance preferences are not part of it and stay in defaults.
struct BrowserAppPreferences: Equatable, Sendable {
    // MARK: - Variables

    static let defaults = BrowserAppPreferences()

    var translationRules = BrowserAutomaticTranslationRules()
    var startupBehavior = BrowserStartupBehavior.defaultBehavior
    var savedTabClosePolicy = BrowserDurableTabClosePolicy.resumeLastLocation
    var offersTranslation = true
    var automaticallyTranslates = false
    var checksSpelling = false
    var automaticallyEntersPictureInPicture = true
    var savedTabFaviconReturnsToSavedURL = false
    var splitFocusFollowsMouse = false

    // MARK: - Initializers

    init() {}
}

/// Decoding is tolerant field by field, so a value a newer build wrote can never
/// stop the session from loading.
extension BrowserAppPreferences: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaults
        func flag(_ key: CodingKeys, _ value: Bool) -> Bool {
            (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? value
        }
        translationRules =
            (try? container.decodeIfPresent(BrowserAutomaticTranslationRules.self, forKey: .translationRules))
            ?? fallback.translationRules
        startupBehavior = container.decodeTolerantly(.startupBehavior, default: fallback.startupBehavior)
        savedTabClosePolicy = container.decodeTolerantly(.savedTabClosePolicy, default: fallback.savedTabClosePolicy)
        offersTranslation = flag(.offersTranslation, fallback.offersTranslation)
        automaticallyTranslates = flag(.automaticallyTranslates, fallback.automaticallyTranslates)
        checksSpelling = flag(.checksSpelling, fallback.checksSpelling)
        automaticallyEntersPictureInPicture = flag(
            .automaticallyEntersPictureInPicture, fallback.automaticallyEntersPictureInPicture)
        savedTabFaviconReturnsToSavedURL = flag(
            .savedTabFaviconReturnsToSavedURL, fallback.savedTabFaviconReturnsToSavedURL)
        splitFocusFollowsMouse = flag(.splitFocusFollowsMouse, fallback.splitFocusFollowsMouse)
    }
}
