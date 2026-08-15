import SwiftUI

struct BrowserManualSetupAddressRow: View {
    @Binding var plan: BrowserManualSetupPlan
    let spaceID: SpaceID
    @Bindable var model: BrowserManualSetupModel

    var body: some View {
        HStack(spacing: BrowserManualSetupSiteEditorMetrics.controlSpacing) {
            TextField("example.com", text: $model.address)
                .crestTextField()
                .submitLabel(.done)
                .onSubmit(addTab)
                .accessibilityIdentifier(
                    BrowserManualSetupAccessibilityID.address
                )

            Button(action: addTab) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(
                .crestIcon(
                    tint: CrestBrandTheme.accent,
                    isProminent: true
                )
            )
            .disabled(!model.canAddAddress)
            .accessibilityLabel("Add site")
            .accessibilityIdentifier(
                BrowserManualSetupAccessibilityID.addTab
            )
        }
    }

    private func addTab() {
        model.addTab(to: spaceID, plan: $plan)
    }
}

#Preview("Manual Setup Address Row") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan

    BrowserManualSetupAddressRow(
        plan: $plan,
        spaceID: BrowserManualSetupPreviewFixture.spaceID,
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 480)
    .padding()
}
