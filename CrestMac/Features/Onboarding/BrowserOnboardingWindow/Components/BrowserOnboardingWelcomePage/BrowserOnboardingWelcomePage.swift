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

                VStack(alignment: .leading, spacing: 18) {
                    Text("Welcome to Crest")
                        .font(.headline)
                        .foregroundStyle(BrowserOnboardingPalette.coral)
                    Text("Set up your Spaces")
                        .font(BrowserOnboardingTypography.display(52))
                        .foregroundStyle(BrowserOnboardingPalette.ink)
                    Text("Organize your browsing into Spaces, each with its own tabs and appearance.")
                        .font(BrowserOnboardingTypography.sans(18, weight: .regular))
                        .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                BrowserSpaceAppearanceHero(
                    branding: .house(.winter, symbol: ""), symbol: "", name: String(localized: "Personal")
                )
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
