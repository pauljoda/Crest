import Foundation
import WebKit

/// What a page does with one navigation. Everything except a hand-off is a plain
/// WebKit policy; a hand-off needs the destination back so the page can cancel
/// and pass the URL to the platform's opener.
enum BrowserNavigationDecision: Equatable {
    case policy(WKNavigationActionPolicy)
    case handOffToSystem(URL)
}
