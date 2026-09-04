import Foundation
import WebKit

/// The trigger half of Crest's first-party-for-cookies rule, shared by every
/// Crest-owned extension web view.
///
/// It answers one question at navigation time — is this a subframe load of a
/// site this extension holds host permission for — and, when it is, waits for
/// the Space's cookie jar to be rewritten before the frame is allowed to go.
/// Waiting is the whole point: the frame's own navigation is the first request
/// that needs the cookie, so a rewrite that landed afterwards would still hand
/// the site a logged-out document.
///
/// The question is asked synchronously and answers `nil` for almost every
/// navigation an extension page makes, so the common case never pays for a
/// deferred decision.
@MainActor
struct BrowserExtensionFramedSiteCookieAccess {
    private let context: WKWebExtensionContext
    private let clientID: BrowserExtensionServiceClientID
    private let spaceID: SpaceID
    private weak var service: (any BrowserExtensionCookieAccessHandling)?

    /// `nil` when the pool has no cookie-access service, so a page assembled
    /// for a test or a preview carries no seam at all.
    init?(
        configuration: BrowserExtensionPageConfiguration,
        spaceID: SpaceID,
        service: (any BrowserExtensionCookieAccessHandling)?
    ) {
        guard let service else { return nil }
        context = configuration.context
        clientID = configuration.clientID
        self.spaceID = spaceID
        self.service = service
    }

    /// The host this navigation needs relaxed, or `nil` when it needs nothing.
    func hostRequiringRewrite(for navigationAction: WKNavigationAction) -> String? {
        // A main-frame load is the extension page itself; `nil` is a new
        // window, which leaves this document entirely. Neither frames a site.
        guard navigationAction.targetFrame?.isMainFrame == false else { return nil }
        return hostRequiringRewrite(for: navigationAction.request.url)
    }

    func hostRequiringRewrite(for url: URL?) -> String? {
        guard service != nil,
            let url,
            let host = BrowserExtensionCookieAccessPolicy.host(for: url),
            // The user granted these hosts at install. Anything else the page
            // frames stays exactly as WebKit decided it.
            context.hasAccess(to: url)
        else { return nil }
        return host
    }

    func relaxCookies(for host: String) async {
        await service?.relaxCookies(for: host, client: clientID, in: spaceID)
    }
}
