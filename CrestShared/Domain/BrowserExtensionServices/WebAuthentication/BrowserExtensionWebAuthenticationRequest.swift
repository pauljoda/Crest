import Foundation

/// One `identity.launchWebAuthFlow` call.
struct BrowserExtensionWebAuthenticationRequest: Equatable, Hashable, Sendable {
    /// The provider's authorization page, opened to begin the flow.
    let authorizationURL: URL
    let callback: BrowserExtensionWebAuthenticationCallback
    /// Chrome's `interactive: false` maps onto this: an ephemeral session keeps
    /// the flow out of the person's shared cookie jar.
    let prefersEphemeralSession: Bool

    init(
        authorizationURL: URL,
        callback: BrowserExtensionWebAuthenticationCallback,
        prefersEphemeralSession: Bool = false
    ) {
        self.authorizationURL = authorizationURL
        self.callback = callback
        self.prefersEphemeralSession = prefersEphemeralSession
    }
}
