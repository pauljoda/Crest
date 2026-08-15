import Foundation

/// The port backing Crest's emulated `chrome.notifications` namespace.
///
/// WebKit does not expose `notifications` through `WKWebExtension`, so the
/// namespace is polyfilled into extension background scripts and forwarded to
/// this port over the native-messaging bridge. Every entry point is scoped to
/// the calling extension: one extension can neither observe, enumerate, nor
/// clear another extension's notifications.
@MainActor
protocol BrowserExtensionNotificationHandling: AnyObject {
    /// Prompts for notification authorization when it is still undetermined.
    func requestAuthorization() async -> BrowserExtensionNotificationAuthorization

    /// The current authorization state without prompting.
    func currentAuthorization() async -> BrowserExtensionNotificationAuthorization

    /// Presents `request` on behalf of `client`.
    ///
    /// Backs `chrome.notifications.create`. A muted or denied host returns
    /// ``BrowserExtensionNotificationPostOutcome/authorizationDenied`` rather
    /// than throwing, so background scripts that ignore rejected promises still
    /// behave predictably.
    func post(
        _ request: BrowserExtensionNotificationRequest,
        from client: BrowserExtensionServiceClientID
    ) async -> BrowserExtensionNotificationPostOutcome

    /// Withdraws one of `client`'s notifications, reporting whether it was
    /// presented. Backs `chrome.notifications.clear`.
    @discardableResult
    func clear(
        notificationIdentifier: String,
        from client: BrowserExtensionServiceClientID
    ) async -> Bool

    /// Withdraws every notification `client` currently has on screen.
    func clearAll(from client: BrowserExtensionServiceClientID) async

    /// The extension-authored identifiers `client` currently has on screen.
    /// Backs `chrome.notifications.getAll`.
    func presentedNotificationIdentifiers(
        for client: BrowserExtensionServiceClientID
    ) async -> [String]

    /// Interactions with `client`'s notifications, for
    /// `onClicked`, `onButtonClicked`, and `onClosed`.
    ///
    /// Each call returns an independent stream; finishing or cancelling one
    /// leaves the others running.
    func events(
        for client: BrowserExtensionServiceClientID
    ) -> AsyncStream<BrowserExtensionNotificationEvent>
}
