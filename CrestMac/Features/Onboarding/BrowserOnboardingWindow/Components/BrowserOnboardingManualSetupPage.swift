import SwiftUI

struct BrowserOnboardingManualSetupPage: View {
    let flow: BrowserOnboardingFlow
    let browserSession: BrowserSession
    @Binding var selectedSpaceID: SpaceID?
    let back: () -> Void

    var body: some View {
        if flow.manualPlan != nil {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shape your Spaces")
                        .font(
                            BrowserOnboardingTypography.sans(
                                14,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(CrestBrandTheme.textDisplay)
                    Text("Customize the look, then add only the tabs you want.")
                        .font(
                            BrowserOnboardingTypography.sans(
                                11,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .frame(height: 64)
                .background(CrestBrandTheme.canvas)

                BrowserManualSetupView(
                    plan: manualPlanBinding,
                    selectedSpaceID: $selectedSpaceID,
                    existingSession: browserSession
                )
                .accessibilityIdentifier("manual-setup-editor")
                .background(CrestBrandTheme.surface)

                HStack {
                    if !flow.didCommitImportInCurrentRun {
                        Button("Back", action: back)
                            .buttonStyle(
                                BrowserOnboardingSecondaryButtonStyle()
                            )
                            .accessibilityIdentifier("onboarding-back")
                    }
                    Spacer()
                    if let message = flow.failure?.message {
                        Label {
                            BrowserOnboardingFailureMessage(message: message)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(
                            BrowserOnboardingTypography.sans(
                                11,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .accessibilityIdentifier("onboarding-workflow-error")
                    } else {
                        Text(
                            "Existing tabs stay in place. Only the changes shown here are saved."
                        )
                        .font(
                            BrowserOnboardingTypography.sans(
                                11,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button("Save Setup", action: flow.commitManualSetup)
                        .buttonStyle(BrowserOnboardingPrimaryButtonStyle())
                        .controlSize(.large)
                        .disabled(flow.isCommittingImport)
                        .accessibilityIdentifier(
                            "onboarding-confirm-manual-setup"
                        )
                }
                .padding(18)
                .background(CrestBrandTheme.canvas)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(CrestBrandTheme.line)
                        .frame(height: 1)
                }
            }
        } else {
            ContentUnavailableView(
                "No Spaces to Set Up",
                systemImage: "square.grid.2x2",
                description: Text("Add a Space to continue setting up Crest.")
            )
        }
    }

    private var manualPlanBinding: Binding<BrowserManualSetupPlan> {
        Binding(
            get: {
                flow.manualPlan
                    ?? BrowserManualSetupPlan(existing: browserSession)
            },
            set: { plan in
                flow.updateManualPlan(plan)
            }
        )
    }
}

#Preview("Manual Setup Page") {
    @Previewable @State var selectedSpaceID: SpaceID? =
        BrowserOnboardingWindowPreviewFixture.session.spaces.first?.id
    let fixture = BrowserOnboardingWindowPreviewFixture(
        entryPoint: .manualSetup
    )

    BrowserOnboardingManualSetupPage(
        flow: fixture.flow,
        browserSession: fixture.browser.session,
        selectedSpaceID: $selectedSpaceID,
        back: {}
    )
    .frame(width: 980, height: 604)
}
