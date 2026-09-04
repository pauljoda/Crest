import Foundation

/// The app-side seam for keeping a site's cookies usable inside an extension
/// page that frames it.
///
/// Registration is implicit: a client appears the first time one of its pages
/// frames a site it holds host permission for, and leaves with its context.
/// There is no `register` call, because nothing should be relaxed for an
/// extension that has never framed anything.
///
/// The blast radius is the Space. `spaceID` is carried on every call rather
/// than derived once, so a rewrite can never reach the cookie jar of a Space
/// the extension is not loaded in.
@MainActor
protocol BrowserExtensionCookieAccessHandling: AnyObject {
    /// Records `host` as relaxed for `client` in `spaceID` and rewrites that
    /// Space's cookies for it now.
    func relaxCookies(
        for host: String,
        client: BrowserExtensionServiceClientID,
        in spaceID: SpaceID
    ) async

    /// Drops every host this client had relaxed.
    ///
    /// Cookies already rewritten stay rewritten — the attribute is gone from
    /// the jar and Crest does not invent a `SameSite` value the site never
    /// sent. What stops is the *enforcement*: once no client in the Space
    /// still lists a host, the site is free to re-set a `Lax` cookie and keep
    /// it.
    func unregister(client: BrowserExtensionServiceClientID)
}

/// The cookie jar behind the store, expressed without WebKit so the
/// Application layer keeps its Foundation-only import policy.
@MainActor
protocol BrowserExtensionCookieJarRelaxing: AnyObject {
    /// Rewrites every cookie in `spaceID`'s jar that a request to `host` would
    /// carry, dropping `SameSite` and preserving everything else.
    func relax(host: String, in spaceID: SpaceID) async

    /// Installs, replaces, or — with a `nil` handler — removes the observer
    /// that reports third-party writes to `spaceID`'s jar.
    ///
    /// The handler is what makes this survive a login: the response that
    /// establishes a session re-sets the same cookies with `SameSite=Lax`, and
    /// without a second pass the frame would be logged out again the moment it
    /// signed in.
    func observe(spaceID: SpaceID, onChange: (@MainActor () -> Void)?)
}
