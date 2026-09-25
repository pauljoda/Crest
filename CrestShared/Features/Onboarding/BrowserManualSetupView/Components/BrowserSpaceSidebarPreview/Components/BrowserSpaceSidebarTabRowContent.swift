import SwiftUI

struct BrowserSpaceSidebarTabRowContent: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.sidebarSpacePresentation) private var presentation

    let tabScale: Double
    let appearance: BrowserTabAppearance

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
        .font(
            .system(
                size: BrowserSidebarDensityPolicy.bodySize(touch: capabilities.supportsTouch)
                    * BrowserSidebarDensityPolicy.scale(tabScale))
        )
        .frame(
            minHeight: BrowserSidebarDensityPolicy.rowHeight(
                base: BrowserManualSetupSidebarPreviewMetrics.tabHeight, scale: tabScale,
                touch: capabilities.supportsTouch)
        )
        .modifier(
            BrowserTabAppearanceSurface(
                appearance: appearance,
                accent: (appearance.color ?? presentation?.branding.primaryColor
                    ?? .indigo)
                    .color,
                isPinned: false, isSelected: isSelected, isHovering: false))
    }
}

#if DEBUG
    #Preview("Setup tab rows") {
        let tab = BrowserSidebarTabRowPreviewFixture.tab()
        let profileID = BrowserSidebarTabRowPreviewFixture.profileID
        VStack(spacing: 12) {
            BrowserSpaceSidebarTabRowContent(
                tab: tab, profileID: profileID, isSelected: true, tabScale: 1,
                appearance: BrowserTabAppearance())
            BrowserSpaceSidebarTabRowContent(
                tab: tab, profileID: profileID, isSelected: false, tabScale: 1,
                appearance: BrowserTabAppearance())
        }.padding().frame(width: 320)
    }
#endif
