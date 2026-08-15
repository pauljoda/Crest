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

#Preview("Manual Setup Added Tabs") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan

    BrowserManualSetupAddedTabList(
        plan: $plan,
        draft: BrowserManualSetupPreviewFixture.draft,
        tabs: [BrowserManualSetupPreviewFixture.manualTab],
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 620)
    .padding()
}
