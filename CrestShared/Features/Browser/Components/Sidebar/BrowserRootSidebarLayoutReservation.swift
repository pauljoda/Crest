import SwiftUI

/// Reserves the sidebar's width beside the page.
///
/// While the reservation animates, the page keeps the whole row rather than
/// resizing with it, so its web content lays out once per sidebar change
/// instead of on every frame. Beside a leading sidebar the page slides with
/// the reservation; a trailing sidebar covers the page's far end, which stays
/// where it is. The page takes the reserved width once the reservation settles.
struct BrowserRootSidebarLayoutReservation: ViewModifier, Animatable {
    // MARK: - Static Variables

    /// Below a point, an interpolated reservation counts as settled.
    private static let settledTolerance: CGFloat = 0.5

    // MARK: - Variables

    /// The reservation on screen, which SwiftUI interpolates.
    nonisolated var width: CGFloat
    /// The reservation `width` is heading for.
    let settledWidth: CGFloat
    let edge: HorizontalEdge

    @Environment(\.layoutDirection) private var layoutDirection

    nonisolated var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    // MARK: - Initializers

    init(width: CGFloat, edge: HorizontalEdge) {
        self.width = width
        settledWidth = width
        self.edge = edge
    }

    // MARK: - Actions - Layout

    func body(content: Content) -> some View {
        content
            .padding(edge == .leading ? .leading : .trailing, laidOutWidth)
            .offset(x: layoutDirection.leadingOffset(slide))
            // The page's frame changes once at either end of the motion; only
            // the slide follows the animation.
            .animation(nil, value: laidOutWidth)
    }

    /// Nothing while the reservation moves, so the page holds the whole row.
    private var laidOutWidth: CGFloat {
        abs(width - settledWidth) < Self.settledTolerance ? settledWidth : 0
    }

    /// How far the page's leading edge follows a leading sidebar's reservation.
    private var slide: CGFloat {
        edge == .leading ? width - laidOutWidth : 0
    }
}
