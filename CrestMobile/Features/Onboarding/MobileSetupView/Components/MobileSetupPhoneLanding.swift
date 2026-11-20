import SwiftUI

/// The welcome on a phone: Crest's mark, the steps ahead as chips, a
/// greeting and a line on what setup does, then the way in along the
/// bottom, within reach. Where it doesn't fit, as on a phone held sideways,
/// it scrolls, so the way in is always reachable.
struct MobileSetupPhoneLanding<Forward: View, Other: View>: View {
    // MARK: - Variables

    /// The steps the walk takes, ending with starting Crest.
    let steps: [BrowserSetupStep]
    let welcome: BrowserOnboardingWelcomeAction
    let errorMessage: String?
    /// Opens a step from its chip, when the welcome leads straight to one.
    let open: ((BrowserSetupStep) -> Void)?
    /// The way in.
    let forward: Forward
    /// What the welcome offers beside the way in, if anything.
    let other: Other

    // MARK: - Initializers

    init(
        steps: [BrowserSetupStep], welcome: BrowserOnboardingWelcomeAction, errorMessage: String?,
        open: ((BrowserSetupStep) -> Void)?, @ViewBuilder forward: () -> Forward, @ViewBuilder other: () -> Other
    ) {
        self.steps = steps
        self.welcome = welcome
        self.errorMessage = errorMessage
        self.open = open
        self.forward = forward()
        self.other = other()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: MobileSetupPhoneLandingMetrics.inset)
            VStack(spacing: MobileSetupPhoneLandingMetrics.spacing) {
                CrestStartPageMark()
                    .frame(
                        width: MobileSetupPhoneLandingMetrics.markSize, height: MobileSetupPhoneLandingMetrics.markSize
                    )
                    .accessibilityHidden(true)
                BrowserSetupStepChips(steps: steps, current: nil, size: .welcome, open: open)
                Text("Welcome to Crest")
                    .font(CrestTypography.display(MobileSetupPhoneLandingMetrics.titleSize))
                    .tracking(MobileSetupPhoneLandingMetrics.titleTracking)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    welcome.opensCrest
                        ? "Your Spaces came in from iCloud, ready to use."
                        : "Bring your tabs over, then set up your Spaces."
                )
                .font(CrestTypography.sans(MobileSetupPhoneLandingMetrics.bodySize, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, MobileSetupPhoneLandingMetrics.inset)
            Spacer(minLength: MobileSetupPhoneLandingMetrics.inset)
            VStack(spacing: CrestSpacing.medium) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(CrestColor.danger)
                        .multilineTextAlignment(.center)
                }
                forward
                other
            }
            .controlSize(.extraLarge)
            .padding(MobileSetupPhoneLandingMetrics.footerInset)
        }
    }
}

enum MobileSetupPhoneLandingMetrics {
    static let spacing: CGFloat = 22
    static let markSize: CGFloat = 72
    static let titleSize: CGFloat = 44
    /// Display type set tight, as Crest's headlines are.
    static let titleTracking: CGFloat = -0.5
    static let bodySize: CGFloat = 18
    static let inset: CGFloat = 28
    static let footerInset = EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
}
