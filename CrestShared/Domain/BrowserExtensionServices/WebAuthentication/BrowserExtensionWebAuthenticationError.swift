import Foundation

enum BrowserExtensionWebAuthenticationError:
    LocalizedError,
    Equatable,
    Sendable
{
    /// The person dismissed the authentication window.
    case userCanceled
    /// The flow finished without a redirect Crest could match against the
    /// expected prefix.
    case invalidCallback
    /// No window was available to present from, or the system refused to show
    /// the authentication sheet.
    case presentationFailure
    /// The redirect shape cannot be intercepted by the system authentication
    /// session. See ``BrowserExtensionWebAuthenticationHandling`` for why an
    /// `https` redirect on an unassociated host lands here.
    case unsupportedCallback

    var errorDescription: String? {
        switch self {
        case .userCanceled:
            "The sign-in window was closed before it finished."
        case .invalidCallback:
            "Sign-in finished without returning to the expected address."
        case .presentationFailure:
            "Crest couldn’t open a window to sign in with."
        case .unsupportedCallback:
            "Crest can’t intercept that extension’s sign-in redirect address."
        }
    }
}
