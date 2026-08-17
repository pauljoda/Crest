import SwiftUI

struct BrowserManualSetupSpaceNameField: View {
    @Binding var plan: BrowserManualSetupPlan
    let spaceID: SpaceID
    let model: BrowserManualSetupModel

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserManualSetupLayoutMetrics.fieldSpacing
        ) {
            Text("Name")
                .font(.headline)
            TextField(
                "Space name",
                text: model.nameBinding(for: spaceID, plan: $plan)
            )
            .crestTextField()
            .font(.title3)
            .accessibilityIdentifier(
                BrowserManualSetupAccessibilityID.spaceName(spaceID)
            )
        }
    }
}
