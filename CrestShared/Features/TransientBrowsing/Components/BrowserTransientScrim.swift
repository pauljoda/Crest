import SwiftUI

/// The dimmed ground a transient overlay's card floats on.
///
/// Where there is room around the card the scrim is also the way out of it, so
/// it is a button. On a handheld screen the card fills the safe area and the
/// scrim is only whatever shows past its corners — a target a thumb finds by
/// accident — so there it is decoration and the drag gesture dismisses
/// instead.
struct BrowserTransientScrim: View {
    let opacity: Double
    let allowsDismissal: Bool
    let dismiss: () -> Void

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
        Color.black.opacity(opacity)
            .ignoresSafeArea()
            .contentShape(.rect)
    }
}
