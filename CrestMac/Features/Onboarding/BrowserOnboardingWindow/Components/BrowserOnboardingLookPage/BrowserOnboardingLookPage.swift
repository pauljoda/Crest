import SwiftUI

/// The look the Spaces setup makes wear: Crest's own banners and crests, a
/// modern gradient and icon, or a simple tinted sidebar with dots for Spaces,
/// each shown as a window. Choosing one restyles the stage and every preview
/// from here on, and gives Crest's customization that style.
struct BrowserOnboardingLookPage: View {
    let look: SetupLook
    let choose: (SetupLook) -> Void
    let back: BrowserOnboardingBackAction
    let continueSetup: () -> Void

    /// The size each window takes: an equal share of the stage less the gaps,
    /// no taller than the stage leaves under the name.
    private func cardSize(in stage: CGSize) -> CGSize {
        let count = CGFloat(SetupLook.all.count)
        let width = min(
            (stage.width - BrowserOnboardingLookMetrics.spacing * (count - 1)) / count,
            BrowserOnboardingLookMetrics.maximumWidth)
        let height = min(width * 0.82, stage.height - 70)
        return CGSize(width: min(width, height / 0.82), height: height)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserOnboardingHeadline("Pick your look")
                .padding(.top, 22)
            GeometryReader { geometry in
                let size = cardSize(in: geometry.size)
                HStack(alignment: .top, spacing: BrowserOnboardingLookMetrics.spacing) {
                    ForEach(SetupLook.all, id: \.self) { offered in
                        BrowserOnboardingLookCard(look: offered, isSelected: offered == look, size: size) {
                            choose(offered)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, BrowserOnboardingStageMetrics.pageInset)
            .padding(.vertical, 16)
            BrowserOnboardingFooter(back: back) {
                BrowserOnboardingContinueButton(action: continueSetup)
                    .accessibilityIdentifier("onboarding-look-continue")
            }
        }
    }
}

/// One look as a sidebar beside a page, named underneath.
private struct BrowserOnboardingLookCard: View {
    let look: SetupLook
    let isSelected: Bool
    let size: CGSize
    let select: () -> Void

    /// How far the window is drawn down from the size it is measured at, so
    /// a narrow card shows the whole window rather than a cut of it.
    private var scale: CGFloat {
        min(1, size.width / BrowserOnboardingLookMetrics.windowWidth)
    }

    var body: some View {
        VStack(spacing: 18) {
            Button(action: select) {
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .overlay {
                        BrowserOnboardingWindowPreview(
                            branding: look.previewBranding, symbol: look.previewSymbol,
                            name: String(localized: "Personal"),
                            spaceIcons: BrowserCustomizationStyle.matching(look).spaceIcons, companionLook: look
                        ) {
                            EmptyView()
                        }
                        .frame(width: size.width / scale, height: size.height / scale)
                        .scaleEffect(scale)
                    }
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: BrowserOnboardingWindowPreviewMetrics.cornerRadius, style: .continuous
                        )
                        .strokeBorder(isSelected ? CrestBrandPalette.butter : .clear, lineWidth: 4)
                    }
                    .contentShape(
                        .rect(cornerRadius: BrowserOnboardingWindowPreviewMetrics.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(look.title))
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("onboarding-look-\(look.name)")
            Text(look.title)
                .font(CrestTypography.display(24))
                .foregroundStyle(CrestBrandTheme.textDisplay)
        }
    }
}

#if DEBUG
    #Preview("Look") {
        BrowserOnboardingStage(step: .look, branding: SetupLook.heraldic.previewBranding) {
            BrowserOnboardingLookPage(
                look: .heraldic, choose: { _ in }, back: BrowserOnboardingBackAction(closes: false, action: {}),
                continueSetup: {})
        }
        .frame(width: 1440, height: 900)
    }
#endif

enum BrowserOnboardingLookMetrics {
    static let spacing: CGFloat = 44
    static let maximumWidth: CGFloat = 720
    /// The width a look's window is measured at before it is drawn down.
    static let windowWidth: CGFloat = 620
}
