import SwiftUI

struct BrowserOnboardingWelcomePage: View {
    let progressIsChecking: Bool
    let cloudPhase: BrowserCloudSyncPhase
    let hasCompletedSetup: Bool
    let hasDisposableSeedState: Bool
    let continueSetup: () -> Void
    let openCrest: () -> Void

    private var action: BrowserOnboardingWelcomeAction {
        BrowserOnboardingWelcomePolicy.action(
            progressIsChecking: progressIsChecking,
            cloudPhase: cloudPhase,
            hasCompletedSetup: hasCompletedSetup
        )
    }

    private var cloudStatusDetail: String {
        if hasCompletedSetup {
            return "Your existing Crest setup is ready."
        }
        if !hasDisposableSeedState {
            return "Your existing Spaces are ready to customize."
        }
        if case .failed = cloudPhase {
            return "iCloud is unavailable right now; you can still set up this Mac."
        }
        return "No existing setup was found."
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                CrestStartPageMark()
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 12) {
                    Text("WELCOME TO CREST")
                        .font(
                            BrowserOnboardingTypography.sans(
                                11,
                                weight: .bold
                            )
                        )
                        .tracking(2.2)
                        .foregroundStyle(BrowserOnboardingPalette.coral)
                    Text("Welcome to Crest")
                        .font(BrowserOnboardingTypography.display(46))
                        .foregroundStyle(BrowserOnboardingPalette.ink)
                    Text(
                        "Bring your browser with you—without bringing over the clutter."
                    )
                    .font(
                        BrowserOnboardingTypography.sans(17, weight: .medium)
                    )
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Label(
                    "Review every Space and tab before anything changes",
                    systemImage: "checklist"
                )
                .font(BrowserOnboardingTypography.sans(14, weight: .medium))
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                Label(
                    "Your setup and browser data sync privately with iCloud",
                    systemImage: "icloud"
                )
                .font(BrowserOnboardingTypography.sans(14, weight: .medium))
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)

                BrowserOnboardingWelcomeCallToAction(
                    action: action,
                    cloudStatusDetail: cloudStatusDetail,
                    perform: performAction
                )
                Spacer()
            }
            .frame(maxWidth: 430, alignment: .leading)
            .padding(52)
            .background(BrowserOnboardingPalette.paper)

            ZStack {
                BrowserOnboardingPalette.parchment
                BrowserOnboardingHeroPreview()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(38)
            }
        }
    }

    private func performAction() {
        switch action {
        case .checking:
            break
        case .setup:
            continueSetup()
        case .open:
            openCrest()
        }
    }
}

#Preview("Welcome Page") {
    BrowserOnboardingWelcomePage(
        progressIsChecking: false,
        cloudPhase: .ready,
        hasCompletedSetup: false,
        hasDisposableSeedState: true,
        continueSetup: {},
        openCrest: {}
    )
    .frame(width: 980, height: 604)
}
