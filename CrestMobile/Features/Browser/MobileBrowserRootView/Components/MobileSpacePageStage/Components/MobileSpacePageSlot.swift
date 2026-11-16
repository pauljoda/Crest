import SwiftUI

/// Places one Space's card in the page area as far along as the Space pager
/// has moved it, or, where cards fade, makes it as opaque as the pager's
/// position has it. Only this modifier reads the position, so a moving pager
/// redraws the offsets and opacities and nothing beneath them.
struct MobileSpacePageSlot: ViewModifier {
    let motion: MobileSpacePageMotion
    /// The Space the card is of, or nil for a page area showing none.
    let spaceID: UUID?
    /// Whether the card is the shown Space's, which a sliding page area draws
    /// above the others.
    let isShown: Bool

    func body(content: Content) -> some View {
        content.modifier(
            MobileSpacePagePlacement(motion: motion, spaceID: spaceID, isShown: isShown, position: motion.position))
    }
}

/// One card's offset, opacity and stacking at a position of the strip. The
/// position is its animatable value, so a fade the pager jumped through is
/// worked out frame by frame by the same rule as one it moved through.
private struct MobileSpacePagePlacement: ViewModifier, Animatable {
    let motion: MobileSpacePageMotion
    let spaceID: UUID?
    let isShown: Bool
    nonisolated var position: CGFloat

    nonisolated var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: spaceID.map { motion.offset(of: $0, at: position) } ?? 0)
            .opacity(spaceID.map { motion.opacity(of: $0, at: position) } ?? 1)
            .zIndex(stacking)
    }

    /// The shown card above the others where cards slide, and where they
    /// fade, the card fading in above the one it covers.
    private var stacking: Double {
        guard !motion.slides, let spaceID else { return isShown ? 1 : 0 }
        return motion.stacking(of: spaceID, at: position)
    }
}
