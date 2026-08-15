import SwiftUI

struct BrowserManualSetupAddedTabRow: View {
    @Binding var plan: BrowserManualSetupPlan
    let tab: BrowserTab
    let spaceID: SpaceID
    let profileID: UUID
    let model: BrowserManualSetupModel

    var body: some View {
        HStack(spacing: BrowserManualSetupSiteEditorMetrics.addedTabSpacing) {
            TabFaviconView(
                tab: tab,
                profileID: profileID,
                size: BrowserManualSetupSiteEditorMetrics.addedTabIconSize
            )
            Text(tab.title)
                .lineLimit(1)
            Spacer()
            BrowserManualSetupPlacementMenu(
                plan: $plan,
                tab: tab,
                spaceID: spaceID,
                labelSymbol: BrowserManualSetupPlacementPresentation.symbol(
                    for: tab.placement
                ),
                accessibilityLabel: Text(
                    "Tab placement for \(tab.title)"
                ),
                accessibilityIdentifier:
                    BrowserManualSetupAccessibilityID
                    .placement(tab.id),
                model: model
            )
        }
        .frame(
            minHeight: BrowserManualSetupSiteEditorMetrics.addedTabMinimumHeight
        )
    }
}

#Preview("Manual Setup Added Tab Row") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan

    BrowserManualSetupAddedTabRow(
        plan: $plan,
        tab: BrowserManualSetupPreviewFixture.manualTab,
        spaceID: BrowserManualSetupPreviewFixture.spaceID,
        profileID: BrowserManualSetupPreviewFixture.profileID,
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 560)
    .padding()
}
