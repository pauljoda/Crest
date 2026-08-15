import AppKit
import AuthenticationServices

/// Supplies the window `ASWebAuthenticationSession` presents its sheet from.
///
/// The anchor is resolved before the session starts and handed here, following
/// the same weak-window discipline as `BrowserExtensionPopupAnchor`: the
/// provider must not keep a window alive, and a window that closed mid-flow
/// must not be returned.
@MainActor
final class BrowserExtensionWebAuthenticationAnchorProvider:
    NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    private weak var anchor: NSWindow?

    func setAnchor(_ window: NSWindow?) {
        anchor = window
    }

    /// The protocol requires a non-optional anchor. A detached window is
    /// returned only in the window-closed-mid-flow case, where the alternative
    /// would be trapping; the session then fails with a presentation error,
    /// which the service maps to a typed failure.
    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}
