import SwiftUI

/// The window chrome that moves between the sidebar and the top of the page
/// as the address bar changes place. Both places draw the same controls under
/// one of these identities, so switching carries them from one place to the
/// other rather than fading one set out and another in.
enum BrowserWindowChromeMorph: Hashable, Sendable {
    /// Back, forward and reload.
    case navigation
    /// The address field.
    case addressField

    // MARK: - Static Variables

    /// How the chrome arrives in its new place and leaves its old one. The
    /// arriving copy shows at once, carried from the old frame to the new.
    /// The leaving copy rides along on the same frame at full strength and
    /// only fades as the two meet, so whichever of them a container clips,
    /// the controls stay solid all the way across.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: .opacity.animation(
                .linear(duration: handoffFade).delay(CrestMotion.chromeTransition - handoffFade)))
    }

    /// How long the leaving copy takes to fade once the two have met.
    private static let handoffFade: TimeInterval = 0.06
}
