import SwiftUI

struct BrowserManualSetupSiteEditor: View {
    @Binding var plan: BrowserManualSetupPlan
    let spaceID: SpaceID
    let existingSession: BrowserSession
    let model: BrowserManualSetupModel

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserManualSetupSiteEditorMetrics.sectionSpacing
        ) {
            Text("Add a site")
                .font(.headline)
            Text(
                "Type any website, or choose from a few popular starting points."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            BrowserManualSetupAddressRow(
                plan: $plan,
                spaceID: spaceID,
                model: model
            )

            BrowserManualSetupPlacementPicker(model: model)

            BrowserManualSetupPopularSites(
                plan: $plan,
                spaceID: spaceID,
                existingSession: existingSession,
                model: model
            )

            BrowserManualSetupErrorMessage(message: model.errorMessage)
        }
    }
}

#Preview("Manual Setup Site Editor") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan

    BrowserManualSetupSiteEditor(
        plan: $plan,
        spaceID: BrowserManualSetupPreviewFixture.spaceID,
        existingSession: BrowserManualSetupPreviewFixture.existingSession,
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 620)
    .padding()
}
