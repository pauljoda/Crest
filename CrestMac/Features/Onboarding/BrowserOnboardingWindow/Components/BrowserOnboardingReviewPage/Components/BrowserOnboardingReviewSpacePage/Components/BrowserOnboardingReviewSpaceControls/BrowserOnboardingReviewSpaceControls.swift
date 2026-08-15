import SwiftUI

struct BrowserOnboardingReviewSpaceControls: View {
    let flow: BrowserOnboardingFlow
    let browserSession: BrowserSession
    let application: BrowserImportApplication?
    let plan: BrowserImportReviewPlan
    let review: BrowserImportSpaceReview
    @Binding var selectedSourceSpaceID: SpaceID?

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                BrowserOnboardingReviewSourcePicker(
                    applicationName: application?.name ?? "browser",
                    spaces: plan.spaces,
                    currentSpaceID: review.id,
                    sourceSpaceName: review.sourceSpace.name,
                    selectedSpaceID: $selectedSourceSpaceID
                )

                Button(action: toggleSpaceInclusion) {
                    Image(
                        systemName: review.isIncluded ? "arrow.right" : "xmark"
                    )
                }
                .buttonStyle(
                    .crestIcon(
                        tint: BrowserOnboardingPalette.coral,
                        isProminent: true
                    )
                )
                .accessibilityLabel(
                    review.isIncluded
                        ? "Skip this Space"
                        : "Include this Space"
                )

                BrowserOnboardingReviewDestinationPicker(
                    spaces: browserSession.spaces,
                    destination: destinationBinding,
                    destinationName: flow.destinationName(
                        for: review.destination
                    )
                )
            }
            .offset(y: -10)

            Toggle("Import this Space", isOn: spaceInclusionBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(BrowserOnboardingPalette.coral)

            Text(review.isIncluded ? "Move Space" : "Skip Space")
                .font(BrowserOnboardingTypography.sans(10, weight: .bold))
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)

            if application?.supportsPasswordImport == true {
                Divider()
                    .frame(width: 74)
                    .padding(.vertical, 4)

                Label(
                    flow.passwordCountLabel(for: review),
                    systemImage: "key.fill"
                )
                .font(BrowserOnboardingTypography.sans(10, weight: .bold))
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)

                Toggle(
                    "Import passwords for \(review.sourceSpace.name)",
                    isOn: passwordInclusionBinding
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(BrowserOnboardingPalette.coral)
                .disabled(
                    !review.isIncluded
                        || flow.passwordCountsBySourceSpace[
                            review.id,
                            default: 0
                        ] == 0
                )
                .accessibilityValue(
                    review.includesPasswords ? "On" : "Off"
                )
            }
        }
        .frame(width: 228)
    }

    private var destinationBinding: Binding<BrowserImportDestination> {
        Binding(
            get: {
                flow.plan?.spaces.first { $0.id == review.id }?.destination
                    ?? review.destination
            },
            set: { flow.setDestination($0, for: review.id) }
        )
    }

    private var spaceInclusionBinding: Binding<Bool> {
        Binding(
            get: { review.isIncluded },
            set: { flow.setSpaceIncluded($0, in: review.id) }
        )
    }

    private var passwordInclusionBinding: Binding<Bool> {
        Binding(
            get: { review.includesPasswords },
            set: { flow.setPasswordsIncluded($0, in: review.id) }
        )
    }

    private func toggleSpaceInclusion() {
        flow.setSpaceIncluded(!review.isIncluded, in: review.id)
    }
}

#Preview("Review Space Controls") {
    @Previewable @State var selectedSourceSpaceID: SpaceID? =
        BrowserOnboardingWindowPreviewFixture.reviewPlan.spaces.first?.id
    let plan = BrowserOnboardingWindowPreviewFixture.reviewPlan
    let fixture = BrowserOnboardingWindowPreviewFixture(plan: plan)

    BrowserOnboardingReviewSpaceControls(
        flow: fixture.flow,
        browserSession: fixture.browser.session,
        application: .arc,
        plan: plan,
        review: plan.spaces[0],
        selectedSourceSpaceID: $selectedSourceSpaceID
    )
    .padding(40)
    .background(BrowserOnboardingPalette.parchment)
}
