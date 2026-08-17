import SwiftUI

struct MobileCompactNewTabPrompt: View {
    let namespace: Namespace.ID
    let geometryID: SpaceID
    let transitionEnded: (CGSize) -> Void
    let openNewTab: () -> Void

    var body: some View {
        Button(action: openNewTab) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text("Search or enter website")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID(geometryID, in: namespace)
        .matchedGeometryEffect(id: geometryID, in: namespace)
        .modifier(
            MobileCompactChromeTransitionModifier(
                transition: .revealPage,
                transitionEnded: transitionEnded
            )
        )
        .accessibilityLabel("New tab")
        .accessibilityHint("Opens a new Start Page. Swipe down to return to the selected tab.")
        .accessibilityIdentifier("new-tab-prompt")
    }
}
