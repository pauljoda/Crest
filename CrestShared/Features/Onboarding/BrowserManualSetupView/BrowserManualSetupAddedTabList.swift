import SwiftUI

struct BrowserManualSetupAddedTabList: View {
    @Binding var plan: BrowserManualSetupPlan
    let draft: BrowserManualSetupSpaceDraft
    let tabs: [BrowserTab]
    let model: BrowserManualSetupModel

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserManualSetupLayoutMetrics.fieldSpacing
        ) {
            Text("Added in this setup")
                .font(.headline)
            ForEach(tabs) { tab in
                BrowserManualSetupAddedTabRow(
                    plan: $plan,
                    tab: tab,
                    spaceID: draft.id,
                    profileID: draft.profile.id,
                    model: model
                )
            }
        }
    }
}

private struct BrowserManualSetupAddedTabRow: View {
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
