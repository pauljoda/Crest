import SwiftUI

struct BrowserOnboardingWelcomeCallToAction: View {
    let action: BrowserOnboardingWelcomeAction
    let cloudStatusDetail: String
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: perform) {
                HStack {
                    if action == .checking {
                        ProgressView().controlSize(.small)
                    }
                    Text(action == .open ? "Open Crest" : "Continue")
                    Image(systemName: "arrow.right")
                }
                .frame(minWidth: 150)
            }
            .buttonStyle(BrowserOnboardingPrimaryButtonStyle())
            .controlSize(.large)
            .disabled(action == .checking)
            .accessibilityLabel(
                action == .open ? Text("Open Crest") : Text("Continue")
            )
            .accessibilityIdentifier("onboarding-welcome-continue")

            Text(
                action == .checking
                    ? "Checking iCloud for an existing Crest setup…"
                    : cloudStatusDetail
            )
            .font(BrowserOnboardingTypography.sans(11, weight: .medium))
            .foregroundStyle(BrowserOnboardingPalette.inkSoft.opacity(0.72))
        }
    }
}

#Preview("Welcome Action") {
    BrowserOnboardingWelcomeCallToAction(
        action: .setup,
        cloudStatusDetail: "No existing setup was found.",
        perform: {}
    )
    .padding()
}
