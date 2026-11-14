import SwiftUI

/// A part of the address field, its address or a site control, that pops out
/// when the field shows another Space, with the new Space's popping in once
/// it is out. The field itself stays put.
///
/// A container rather than a modifier: the part popping out keeps the
/// contents it had, where a modifier's content would show the new Space's in
/// both.
struct BrowserAddressSwap<Content: View>: View {
    // MARK: - Static Variables

    /// How small a part shrinks to as it pops out, and grows from as it pops
    /// in.
    private static var poppedScale: CGFloat { 0.8 }

    // MARK: - Variables

    /// The Space whose contents the part shows, or nil for a Space showing
    /// only the prompt. Another value swaps the part.
    let swapID: UUID?
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        // The part popping out and the one popping in share one place.
        ZStack {
            content
                .id(swapID)
                .transition(swap)
        }
        // A part that comes or goes on its own, such as a site control once
        // a page is ready, pops as the change around it animates, and not
        // at all as editing starts or ends.
        .transition(popped)
    }

    private var popped: AnyTransition {
        .scale(scale: Self.poppedScale).combined(with: .opacity)
    }

    /// The old Space's part popping out and the new one's popping in once
    /// it is out, each with its own timing.
    private var swap: AnyTransition {
        .asymmetric(
            insertion: popped.animation(CrestMotion.addressSwapIn.unlessReducingMotion(reduceMotion)),
            removal: popped.animation(CrestMotion.addressSwapOut.unlessReducingMotion(reduceMotion))
        )
    }
}
