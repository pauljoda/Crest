import SwiftUI

struct BrowserManualSetupEditorHeader: View {
    @Binding var plan: BrowserManualSetupPlan
    let draft: BrowserManualSetupSpaceDraft
    let model: BrowserManualSetupModel

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserManualSetupLayoutMetrics.headingSpacing
        ) {
            HStack {
                Text("Make this Space yours")
                    .font(.title2.bold())
                Spacer()
                if draft.isNew, plan.spaces.count > 1 {
                    Button(
                        "Remove",
                        systemImage: "trash",
                        role: .destructive,
                        action: removeSpace
                    )
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(
                        "Remove \(model.displayName(draft.customization.name))"
                    )
                }
            }
            Text(
                "Name it, choose its look, and add the sites you want ready on day one."
            )
            .foregroundStyle(.secondary)
        }
    }

    private func removeSpace() {
        model.removeSpace(draft.id, plan: $plan)
    }
}

#Preview("Manual Setup Editor Header") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan

    BrowserManualSetupEditorHeader(
        plan: $plan,
        draft: BrowserManualSetupPreviewFixture.draft,
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 620)
    .padding()
}
