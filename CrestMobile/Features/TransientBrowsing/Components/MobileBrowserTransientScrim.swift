import SwiftUI

struct MobileBrowserTransientScrim: View {
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
