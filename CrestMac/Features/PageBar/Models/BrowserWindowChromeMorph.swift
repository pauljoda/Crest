import SwiftUI

/// The window chrome that moves between the sidebar and the top of the page
/// as the address bar changes place.
///
/// Both surfaces animate purely with GPU-composited offset and opacity
/// transitions rather than cross-container `matchedGeometryEffect`, avoiding
/// per-frame root `NSHostingView` layout passes during placement swaps.
enum BrowserWindowChromeMorph: Hashable, Sendable {
    /// Back, forward and reload.
    case navigation
    /// The address field.
    case addressField

    // MARK: - Static Variables

    static var transition: AnyTransition {
        topBarTransition(fromLeading: true)
    }

    /// GPU-composited glide for the top address bar arriving from or departing
    /// toward the sidebar edge.
    static func topBarTransition(fromLeading: Bool) -> AnyTransition {
        let dx: CGFloat = fromLeading ? -32 : 32
        return .asymmetric(
            insertion: .offset(x: dx, y: 8).combined(with: .opacity),
            removal: .offset(x: dx, y: 8).combined(with: .opacity)
        )
    }

    /// GPU-composited glide for the sidebar navigation and address strip
    /// arriving from or departing toward the top of the page.
    static func sidebarTransition(towardTrailing: Bool) -> AnyTransition {
        let dx: CGFloat = towardTrailing ? 28 : -28
        return .asymmetric(
            insertion: .offset(x: dx, y: -10).combined(with: .opacity),
            removal: .offset(x: dx, y: -10).combined(with: .opacity)
        )
    }
}
