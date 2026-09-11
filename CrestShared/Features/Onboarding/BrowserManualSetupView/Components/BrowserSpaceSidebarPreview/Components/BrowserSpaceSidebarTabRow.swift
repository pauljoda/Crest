import SwiftUI

struct BrowserSpaceSidebarTabRow: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool
    @Environment(\.sidebarSpacePresentation) private var presentation

    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults)
    private var tabScale = 1.0

    var body: some View {
        HStack(spacing: BrowserManualSetupSidebarPreviewMetrics.tabSpacing) {
            TabFaviconView(
                tab: tab,
                profileID: profileID,
                size: BrowserManualSetupSidebarPreviewMetrics.tabIconSize * BrowserSidebarDensityPolicy.scale(tabScale)
            )
            Text(tab.title)
                .lineLimit(1)
            Spacer()
        }
        .padding(
            .horizontal,
            BrowserManualSetupSidebarPreviewMetrics.tabHorizontalPadding
        )
        .font(.system(size: BrowserSidebarDensityPolicy.bodySize * BrowserSidebarDensityPolicy.scale(tabScale)))
        .frame(
            minHeight: BrowserSidebarDensityPolicy.rowHeight(
                base: BrowserManualSetupSidebarPreviewMetrics.tabHeight, scale: tabScale,
                touch: BrowserSidebarDensityPolicy.usesTouch)
        )
        .modifier(
            BrowserTabAppearanceSurface(
                appearance: BrowserDeviceAppearanceStore.shared.tabs,
                accent: (BrowserDeviceAppearanceStore.shared.tabs.color ?? presentation?.branding.primaryColor
                    ?? .indigo)
                    .color,
                isPinned: false, isSelected: isSelected, isHovering: false))
    }
}
