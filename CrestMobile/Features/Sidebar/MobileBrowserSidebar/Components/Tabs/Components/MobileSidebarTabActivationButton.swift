import SwiftUI

struct MobileSidebarTabActivationButton: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let restoreSavedLocation: (() -> Void)?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label {
                Text(tab.displayTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } icon: {
                HStack(spacing: 3) {
                    TabFaviconView(tab: tab, profileID: profileID, size: 18)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 20)
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if tab.placement == .saved,
                        tab.isAwayFromSavedLocation,
                        let restoreSavedLocation
                    {
                        BrowserTabSavedLocationIndicator(
                            restore: restoreSavedLocation
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityValue(
            BrowserChromeAccessibility.tabValue(isLoaded: isLoaded)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(BrowserTabAccessibilityID.row(tab.id))
    }
}

#Preview("Mobile Sidebar Tab Activation", traits: .sizeThatFitsLayout) {
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileSidebarTabActivationButton(
        tab: fixture.savedTab,
        profileID: fixture.space.profile.id,
        isSelected: true,
        isLoaded: true,
        restoreSavedLocation: {},
        select: {}
    )
    .frame(width: 320)
    .padding()
}
