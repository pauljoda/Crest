import SwiftUI

struct BrowserManualSetupSpacePicker: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?
    let previewSession: BrowserSession?
    let model: BrowserManualSetupModel

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            CrestSpaceIconPicker(
                spaces: plan.spaces.map {
                    model.previewSpace(for: $0, in: previewSession)
                },
                selectedSpaceID: selectedSpaceID,
                selectSpace: select,
                selectionTint: CrestBrandTheme.accent,
                accessibilityIdentifier:
                    BrowserManualSetupAccessibilityID.spacePicker
            ) { space in
                BrowserSpaceSymbolArtwork(
                    space: space,
                    size: BrowserManualSetupLayoutMetrics.spacePickerSymbolSize,
                    lockSize: BrowserManualSetupLayoutMetrics.spacePickerLockSize
                )
            }

            Button("New Space", systemImage: "plus", action: addSpace)
                .labelStyle(.iconOnly)
                .buttonStyle(.crestIcon(tint: CrestBrandTheme.accent))
                .accessibilityIdentifier(
                    BrowserManualSetupAccessibilityID.addSpace
                )
        }
        .fixedSize()
    }

    private func select(_ spaceID: SpaceID) {
        model.select(spaceID, selectedSpaceID: $selectedSpaceID)
    }

    private func addSpace() {
        model.addSpace(
            plan: $plan,
            selectedSpaceID: $selectedSpaceID
        )
    }
}

#Preview("Manual Setup Space Picker") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan
    @Previewable @State var selectedSpaceID =
        BrowserManualSetupPreviewFixture.selectedSpaceID

    BrowserManualSetupSpacePicker(
        plan: $plan,
        selectedSpaceID: $selectedSpaceID,
        previewSession: BrowserManualSetupPreviewFixture.previewSession,
        model: BrowserManualSetupPreviewFixture.model()
    )
    .padding()
}
