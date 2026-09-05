import SwiftUI

struct PinnedTabSelectionButton: View {
    let tab: BrowserTab
    let spaceID: SpaceID
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
                .browserTabResidency(isLoaded: isLoaded)
                .frame(maxWidth: .infinity)
                .frame(height: BrowserPinnedTabReorderLayout.cellHeight)
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
