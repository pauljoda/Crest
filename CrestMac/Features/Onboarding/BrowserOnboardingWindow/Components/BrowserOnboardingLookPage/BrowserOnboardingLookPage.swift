import SwiftUI

/// The look the Spaces setup makes wear: Crest's own banners and crests, or
/// a modern gradient and icon, each shown as a sidebar. Choosing one restyles
/// the stage and every preview from here on.
struct BrowserOnboardingLookPage: View {
    let look: SetupLook
    let choose: (SetupLook) -> Void
    let back: BrowserOnboardingBackAction
    let continueSetup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BrowserOnboardingHeadline("Pick your look")
                .padding(.top, 22)
            Spacer(minLength: 24)
            HStack(alignment: .top, spacing: 80) {
                ForEach(SetupLook.all, id: \.self) { offered in
                    BrowserOnboardingLookCard(look: offered, isSelected: offered == look) {
                        choose(offered)
                    }
                }
            }
            Spacer(minLength: 24)
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
    let select: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: select) {
                HStack(spacing: 0) {
                    BrowserSpaceAppearanceHero(
                        branding: look.previewBranding, symbol: look.previewSymbol,
                        name: String(localized: "Personal")
                    )
                    .frame(width: 250)
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(CrestBrandPalette.paper)
                        .padding(.vertical, 8)
                        .padding(.leading, 8)
                }
                .padding(.trailing, 8)
                .frame(width: 520, height: 540)
                .background(CrestBrandPalette.ink, in: .rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isSelected ? CrestBrandPalette.butter : CrestBrandTheme.line,
                            lineWidth: isSelected ? 4 : CrestLayout.hairline)
                }
                .shadow(color: .black.opacity(0.45), radius: 30, y: 24)
                .contentShape(.rect(cornerRadius: 18, style: .continuous))
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
