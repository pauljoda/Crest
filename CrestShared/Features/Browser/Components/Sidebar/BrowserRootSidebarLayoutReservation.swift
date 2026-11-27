import SwiftUI

struct BrowserRootSidebarLayoutReservation: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let isApproachingDock: Bool

    private var reservesWidth: Bool {
        presentation.reservesSidebarWidth || isApproachingDock
    }

    var body: some View {
        Color.clear
            .frame(
                width: presentation.reservedWidth(
                    for: width,
                    whileApproachingDock: isApproachingDock
                ),
                alignment: .leading
            )
            // Snap the sidebar reservation toggle once underneath the floating
            // sidebar rather than reflowing live web pages and split columns on
            // every animation frame; interactive width drags still track live.
            .transaction(value: reservesWidth) { transaction in
                transaction.animation = nil
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
