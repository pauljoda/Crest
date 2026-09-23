import Foundation

/// A preference a `preferences.set` command names. Raw values are the core
/// record's field names.
enum BrowserAppPreference: String, Codable, Sendable {
    case startupBehavior
    case offersTranslation
    case automaticallyTranslates
    case checksSpelling
    case automaticallyEntersPictureInPicture
    case savedTabClosePolicy
    case savedTabFaviconReturnsToSavedURL
    case splitFocusFollowsMouse
}
