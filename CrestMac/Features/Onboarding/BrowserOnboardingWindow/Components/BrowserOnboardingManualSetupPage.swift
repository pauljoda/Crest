import SwiftUI

struct BrowserOnboardingManualSetupPage: View {
    let flow: BrowserOnboardingFlow
    let browserSession: BrowserSession
    let opensGettingStarted: Bool
    @Binding var selectedSpaceID: SpaceID?
    let back: () -> Void
    let openCrest: () -> Void

    var body: some View {
        BrowserSpaceSetupWizard(
            plan: manualPlanBinding,
            selectedSpaceID: $selectedSpaceID,
            opensGettingStarted: opensGettingStarted,
            back: back,
            finish: {
                flow.commitManualSetup()
                if flow.step == .complete { openCrest() }
            }
        )
        .overlay(alignment: .bottom) {
            if let message = flow.failure?.message {
                BrowserOnboardingFailureMessage(message: message)
                    .foregroundStyle(.red)
                    .padding(.bottom, 76)
            }
        }
        .accessibilityIdentifier("manual-setup-editor")
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
