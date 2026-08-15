import SwiftUI

struct MobileOnboardingWelcomePage: View {
    let action: BrowserOnboardingWelcomeAction
    let primaryTitle: String
    let status: String
    let primaryAction: () -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: nil,
            primaryTitle: primaryTitle,
            primarySystemImage: action == .open
                ? "arrow.right"
                : "chevron.right",
            primaryIdentifier:
                BrowserMobileAccessibilityID.welcomeContinue,
            primaryDisabled: action == .checking,
            showsActivity: action == .checking,
            primaryAction: primaryAction
        ) {
            VStack(spacing: MobileOnboardingLayout.welcomeSpacing) {
                Spacer(
                    minLength: MobileOnboardingLayout.welcomeTopMinimumSpacing
                )

                CrestStartPageMark()
                    .frame(
                        width: MobileOnboardingLayout.crestMarkSize,
                        height: MobileOnboardingLayout.crestMarkSize
                    )
                    .accessibilityHidden(true)

                MobileOnboardingTitle(
                    title: "Meet Crest",
                    detail: "A browser built around Spaces, so work, life, and every project stay separate."
                )

                VStack(spacing: 0) {
                    MobileOnboardingFeatureRow(
                        symbol: "square.grid.2x2",
                        title: "Separate by Space",
                        detail: "Tabs, history, passwords, and settings stay with the Space they belong to."
                    )
                    Divider()
                    MobileOnboardingFeatureRow(
                        symbol: "checklist",
                        title: "Keep a useful sidebar",
                        detail: "Pin essentials, save things for later, and leave the rest temporary."
                    )
                    Divider()
                    MobileOnboardingFeatureRow(
                        symbol: "icloud",
                        title: "Sync privately",
                        detail: "Your setup follows you across your Apple devices with iCloud."
                    )
                }
                .frame(maxWidth: MobileOnboardingLayout.featureListMaximumWidth)

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(
                    minLength: MobileOnboardingLayout.welcomeBottomMinimumSpacing
                )
            }
        }
    }
}

#Preview("Mobile Onboarding — Welcome") {
    MobileOnboardingWelcomePage(
        action: .setup,
        primaryTitle: "Get Started",
        status: "No existing setup was found in iCloud.",
        primaryAction: {}
    )
}
