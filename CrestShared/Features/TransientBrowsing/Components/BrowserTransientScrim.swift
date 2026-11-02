import SwiftUI

/// The dimmed ground a transient overlay's card floats on.
///
/// The scrim is also the way out of the card, so it is a button. How much of it
/// shows is the arrangement's business: a floating card leaves generous ground
/// around itself, a handheld card leaves only the strip past its safe-area
/// insets. Either way a tap that lands outside the card is a tap that meant to
/// leave it.
struct BrowserTransientScrim: View {
    let opacity: Double
    let allowsDismissal: Bool
    var insets = EdgeInsets()
    /// Whether the ground fades in when it appears, as the card grows, instead
    /// of showing at its full opacity from the first frame.
    var fadesIn = false
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        if allowsDismissal {
            Button(action: dismiss) {
                scrim
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        } else {
            scrim
                .accessibilityHidden(true)
        }
    }

    private var scrim: some View {
        Color.black.opacity(shownOpacity)
            .ignoresSafeArea()
            .padding(insets)
            .contentShape(.rect)
            .animation(fade, value: shownOpacity)
            .onAppear { hasAppeared = true }
    }

    /// Zero for the first frame of a fading scrim, so it has somewhere to fade
    /// in from.
    private var shownOpacity: Double {
        fadesIn && !hasAppeared ? 0 : opacity
    }

    private var fade: Animation? {
        fadesIn ? CrestMotion.quickPeekEntrance.unlessReducingMotion(reduceMotion) : nil
    }
}
