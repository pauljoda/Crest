import Foundation

/// The `chrome.history` transition vocabulary.
///
/// Crest records one row per URL rather than one row per visit and keeps no
/// navigation cause, so every synthesized visit reports ``link``. The full set
/// is modelled anyway because the polyfill must emit values the extension's own
/// `switch` statements recognize.
enum BrowserExtensionHistoryTransition:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case link
    case typed
    case autoBookmark = "auto_bookmark"
    case autoSubframe = "auto_subframe"
    case manualSubframe = "manual_subframe"
    case generated
    case autoToplevel = "auto_toplevel"
    case formSubmit = "form_submit"
    case reload
    case keyword
    case keywordGenerated = "keyword_generated"
}
