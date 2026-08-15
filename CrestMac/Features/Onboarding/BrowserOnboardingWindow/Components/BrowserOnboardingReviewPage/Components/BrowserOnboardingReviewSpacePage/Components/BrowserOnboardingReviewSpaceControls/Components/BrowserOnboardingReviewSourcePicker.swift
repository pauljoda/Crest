import SwiftUI

struct BrowserOnboardingReviewSourcePicker: View {
    let applicationName: String
    let spaces: [BrowserImportSpaceReview]
    let currentSpaceID: SpaceID
    let sourceSpaceName: String
    @Binding var selectedSpaceID: SpaceID?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("From \(applicationName)")
                .font(.caption)
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)

            Picker("Source Space", selection: selection) {
                ForEach(spaces) { item in
                    Text(item.sourceSpace.name).tag(item.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)
            .tint(BrowserOnboardingPalette.coral)
            .frame(width: 80)
            .accessibilityValue(sourceSpaceName)
        }
    }

    private var selection: Binding<SpaceID> {
        Binding(
            get: { currentSpaceID },
            set: { selectedSpaceID = $0 }
        )
    }
}

#Preview("Review Source Picker") {
    @Previewable @State var selectedSpaceID: SpaceID? = nil
    let plan = BrowserOnboardingWindowPreviewFixture.reviewPlan

    BrowserOnboardingReviewSourcePicker(
        applicationName: "Arc",
        spaces: plan.spaces,
        currentSpaceID: plan.spaces[0].id,
        sourceSpaceName: plan.spaces[0].sourceSpace.name,
        selectedSpaceID: $selectedSpaceID
    )
    .padding()
}
