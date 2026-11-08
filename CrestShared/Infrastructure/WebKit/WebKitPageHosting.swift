import Foundation
import WebKit

/// The platform's page hosting what WebKit's binding built: it shows the
/// person the core's questions about the page, gets ready for each load the
/// binding runs in the page, asks WebKit what media the page runs when that
/// may have changed, and reads what its credential bridge posts.
@MainActor
protocol WebKitPageHosting: BrowserPromptPresenting {
    /// The binding is about to load `url` in the page as the app's own load,
    /// or to bring the page's history back there: the page shows itself
    /// heading to `url`, and lets that navigation reach what only the app may
    /// load.
    func prepareToLoad(_ url: URL)

    /// Media in the page started, stopped or ended, so the page asks WebKit
    /// what it runs now and tells the core when that changed.
    func mediaActivityMayHaveChanged()

    /// The core asked for a history entry WebKit no longer keeps, so the page
    /// reports its history again, as WebKit keeps it now.
    func historyMayHaveChanged()

    /// The credential bridge posted `message`. A popup shares its opener's
    /// user content controller, so a message from a popup's web view reaches
    /// the opener's handler, which hands it to the popup's page through
    /// `WebKitEngineBinding.page(showing:)`.
    func receiveCredentialMessage(_ message: WKScriptMessage)
    /// Answers a message from the cosmetic bridge in this page's web view,
    /// handed on the same way.
    func receiveCosmeticFilterMessage(_ message: WKScriptMessage)
}
