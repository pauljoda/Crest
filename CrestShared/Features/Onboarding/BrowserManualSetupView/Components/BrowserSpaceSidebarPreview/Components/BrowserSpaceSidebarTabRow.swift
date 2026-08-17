import SwiftUI

struct BrowserSpaceSidebarTabRow: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrowserManualSetupSidebarPreviewMetrics.tabSpacing) {
            TabFaviconView(
                tab: tab,
                profileID: profileID,
                size: BrowserManualSetupSidebarPreviewMetrics.tabIconSize
            )
            Text(tab.title)
                .lineLimit(1)
            Spacer()
        }
        .padding(
            .horizontal,
            BrowserManualSetupSidebarPreviewMetrics.tabHorizontalPadding
        )
        .frame(height: BrowserManualSetupSidebarPreviewMetrics.tabHeight)
        .background(
            isSelected
                ? Color.primary.opacity(
                    BrowserManualSetupSidebarPreviewMetrics
                        .selectedTabFillOpacity
                )
                : .clear,
            in: .rect(
                cornerRadius: BrowserManualSetupSidebarPreviewMetrics
                    .tabCornerRadius,
                style: .continuous
            )
        )
    }
}
