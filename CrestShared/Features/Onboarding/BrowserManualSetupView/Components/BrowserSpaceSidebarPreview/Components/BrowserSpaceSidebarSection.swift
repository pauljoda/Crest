import SwiftUI

struct BrowserSpaceSidebarSection: View {
    let title: String
    let tabs: [BrowserTab]
    let profileID: UUID
    let selectedTabID: TabID?

    var body: some View {
        if !tabs.isEmpty {
            VStack(
                alignment: .leading,
                spacing: BrowserManualSetupSidebarPreviewMetrics.sectionSpacing
            ) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(
                        .horizontal,
                        BrowserManualSetupSidebarPreviewMetrics
                            .sectionHorizontalPadding
                    )
                ForEach(tabs) { tab in
                    BrowserSpaceSidebarTabRow(
                        tab: tab,
                        profileID: profileID,
                        isSelected: tab.id == selectedTabID
                    )
                }
            }
        }
    }
}
