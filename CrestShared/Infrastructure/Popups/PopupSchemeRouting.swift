import Foundation
import WebKit

/// What a new-window request's own URL scheme settles before any pop-up
/// permission is consulted.
///
/// `window.open("mailto:…")` is the case this exists for: the destination belongs
/// to another application, so it must never become a tab. Opening one and then
/// handing the URL off leaves an empty tab behind that the user has to notice and
/// close.
enum BrowserPopupSchemeRouting: Equatable, Sendable {
    /// WebKit can host the destination, so the pop-up policy decides.
    case popupPolicy
    /// Another application owns the destination: hand it off, open no tab.
    case handOffToSystem(URL)
    /// Nothing may load it and nothing may open it.
    case blocked

    /// A popup destination is never app-initiated, so `file:` is refused here for
    /// the same reason it is refused for an ordinary navigation.
    static func classify(destinationURL: URL?) -> Self {
        switch BrowserExternalSchemePolicy.disposition(for: destinationURL) {
        case .webKit:
            return .popupPolicy
        case .blocked:
            return .blocked
        case .handOff:
            guard let destinationURL else { return .blocked }
            return .handOffToSystem(destinationURL)
        }
    }
}
