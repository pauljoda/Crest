import SwiftUI

struct PinnedTabSelectionButton: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let siteTheme: BrowserTabIconAccent?
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            TabFaviconView(tab: tab, profileID: profileID, size: 19)
                .font(.system(size: 17, weight: .medium))
                .saturation(
                    BrowserVisualAccessibilityPolicy.tabResidencySaturation(
                        isLoaded: isLoaded
                    )
                )
                .opacity(
                    BrowserVisualAccessibilityPolicy.tabResidencyOpacity(
                        isLoaded: isLoaded
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: 47)
                .contentShape(.rect)
                .modifier(
                    PinnedTabInteractionSurface(
                        faviconData: tab.displayFaviconData,
                        siteTheme: siteTheme,
                        isSelected: isSelected,
                        isHovering: isHovering
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview("Pinned Tab Selection Button", traits: .sizeThatFitsLayout) {
    @Previewable @State var isSelected = true
    let fixture = PinnedTabGridPreviewFixture()

    PinnedTabSelectionButton(
        tab: fixture.pinnedTab,
        profileID: fixture.space.profile.id,
        isSelected: isSelected,
        isLoaded: false,
        siteTheme: BrowserTabIconAccent(
            red: 0.31,
            green: 0.58,
            blue: 0.96
        ),
        select: { isSelected.toggle() }
    )
    .frame(width: 92)
    .padding()
}
