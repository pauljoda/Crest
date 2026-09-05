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
    /// Records a permitted embedded host and synchronizes its normal and
    /// hosted cookies, relaxing SameSite only in the hosted jar.
    func relaxCookies(
        for host: String,
        client: BrowserExtensionServiceClientID,
        in spaceID: SpaceID
    ) async

    /// Drops every host this client had relaxed.
    ///
    /// Synchronization stops when no remaining client frames the host. Normal
    /// browsing cookies retain their own SameSite attributes throughout.
    func unregister(client: BrowserExtensionServiceClientID)

    /// Removes previously framed hosts whose permission has been revoked.
    func revalidatePermissions(
        for client: BrowserExtensionServiceClientID,
        allowing hostIsPermitted: (String) -> Bool
    )
}

/// The cookie jar behind the store, expressed without WebKit so the
/// Application layer keeps its Foundation-only import policy.
@MainActor
protocol BrowserExtensionCookieJarRelaxing: AnyObject {
    /// Makes a permitted host usable in the separate hosted cookie jar while
    /// preserving normal-tab cookie protection.
    func relax(host: String, in spaceID: SpaceID) async

    /// Updates the live host set before queued synchronization can run.
    func setSynchronizedHosts(_ hosts: Set<String>, in spaceID: SpaceID)

    /// Installs, replaces, or — with a `nil` handler — removes the observer
    /// that reports third-party writes to `spaceID`'s jar.
    ///
    /// The handler is what makes this survive a login: the response that
    /// establishes a session re-sets the same cookies with `SameSite=Lax`, and
    /// without a second pass the frame would be logged out again the moment it
    /// signed in.
    func observe(spaceID: SpaceID, onChange: (@MainActor () -> Void)?)
}
