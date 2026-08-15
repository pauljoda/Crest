import SwiftUI

struct BrowserManualSetupView: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?
    let existingSession: BrowserSession

    @State private var model = BrowserManualSetupModel()

    var body: some View {
        BrowserManualSetupContent(
            plan: $plan,
            selectedSpaceID: $selectedSpaceID,
            existingSession: existingSession,
            model: model
        )
        .onAppear(perform: repairSelection)
        .onChange(of: plan.spaces.map(\.id)) { _, _ in repairSelection() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Set up your Spaces")
    }

    private func repairSelection() {
        model.repairSelection(
            plan: plan,
            selectedSpaceID: $selectedSpaceID
        )
    }
}

#Preview("Manual Space Setup") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan
    @Previewable @State var selectedSpaceID =
        BrowserManualSetupPreviewFixture.selectedSpaceID

    BrowserManualSetupView(
        plan: $plan,
        selectedSpaceID: $selectedSpaceID,
        existingSession: BrowserManualSetupPreviewFixture.existingSession
    )
    .frame(width: 1_080, height: 720)
}
