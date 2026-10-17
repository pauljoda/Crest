import SwiftUI

/// The stage every step of setup plays on: the look's own sidebar field,
/// darkened, under the Crest mark, the progress rail and the step's page.
/// The stage is always dark, whatever the system appearance, so the page
/// reads over any field.
struct BrowserOnboardingStage<Content: View>: View {
    let step: SetupStep
    /// The look the backdrop wears.
    let branding: SpaceBranding
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            BrowserOnboardingBackdrop(branding: branding)
            VStack(spacing: 0) {
                BrowserOnboardingStageHeader(step: step)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The Crest mark and the progress rail over the stage.
private struct BrowserOnboardingStageHeader: View {
    let step: SetupStep

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                CrestStartPageMark()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text(ProductIdentity.name)
                    .font(CrestTypography.sans(14, weight: .bold))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                Spacer()
            }
            BrowserOnboardingProgressRail(step: step)
        }
        .padding(.horizontal, BrowserOnboardingStageMetrics.headerInset)
        .frame(height: BrowserOnboardingStageMetrics.headerHeight)
    }
}

/// The measurements the stage and its pages share.
enum BrowserOnboardingStageMetrics {
    static let headerHeight: CGFloat = 64
    static let headerInset: CGFloat = 28
    /// The inset the footer keeps from the stage's edges.
    static let inset: CGFloat = 40
    /// The inset a page's content keeps from the stage's edges.
    static let pageInset: CGFloat = 120
    /// How far a page's headline sits under the header.
    static let headlineSize: CGFloat = 46
    /// How much the backdrop darkens the field so the page reads over it.
    static let backdropShade = 0.55
}
