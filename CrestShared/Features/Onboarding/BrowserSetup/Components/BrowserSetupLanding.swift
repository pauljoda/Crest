import SwiftUI

/// The welcome, filling setup's window as Crest's website opens: Crest's
/// mark, the steps ahead as colored chips, a greeting, a line on what setup
/// does, and the way in. Nothing else shows while it does, so the way in is
/// the one thing to do.
struct BrowserSetupLanding<Leading: View, Forward: View>: View {
    // MARK: - Variables

    /// The steps the walk takes, ending with starting Crest.
    let steps: [BrowserSetupStep]
    let welcome: BrowserOnboardingWelcomeAction
    /// Opens a step from its chip, when the welcome leads straight to one.
    let open: ((BrowserSetupStep) -> Void)?
    /// What the welcome offers beside the way in, if anything.
    let leading: Leading
    /// The way in.
    let forward: Forward

    // MARK: - Initializers

    init(
        steps: [BrowserSetupStep], welcome: BrowserOnboardingWelcomeAction,
        open: ((BrowserSetupStep) -> Void)? = nil, @ViewBuilder leading: () -> Leading,
        @ViewBuilder forward: () -> Forward
    ) {
        self.steps = steps
        self.welcome = welcome
        self.open = open
        self.leading = leading()
        self.forward = forward()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(spacing: BrowserSetupLandingMetrics.spacing) {
            CrestStartPageMark()
                .frame(width: BrowserSetupLandingMetrics.markSize, height: BrowserSetupLandingMetrics.markSize)
                .accessibilityHidden(true)
            BrowserSetupStepChips(steps: steps, current: nil, size: .welcome, open: open)
            Text("Welcome to Crest")
                .font(CrestTypography.display(BrowserSetupLandingMetrics.titleSize))
                .tracking(BrowserSetupLandingMetrics.titleTracking)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(
                welcome.opensCrest
                    ? "Your Spaces came in from iCloud, ready to use."
                    : "Bring your tabs over, then set up your Spaces."
            )
            .font(CrestTypography.sans(BrowserSetupLandingMetrics.bodySize, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: BrowserSetupLandingMetrics.bodyWidth)
            HStack(spacing: CrestSpacing.medium) {
                leading
                forward
            }
            .controlSize(.extraLarge)
            .padding(.top, CrestSpacing.small)
        }
        .padding(BrowserSetupLandingMetrics.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum BrowserSetupLandingMetrics {
    static let spacing: CGFloat = 26
    static let markSize: CGFloat = 76
    static let titleSize: CGFloat = 84
    /// Display type set tight, as Crest's headlines are.
    static let titleTracking: CGFloat = -1
    static let bodySize: CGFloat = 20
    static let bodyWidth: CGFloat = 560
    static let inset: CGFloat = 48
}
