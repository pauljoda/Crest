import SwiftUI

struct BrowserMacOnboardingTutorialCopy: View {
    let tutorial: BrowserMacOnboardingTutorial

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text(tutorial.eyebrow)
                .font(BrowserOnboardingTypography.sans(11, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(BrowserOnboardingPalette.coral)
                .accessibilityIdentifier(
                    "onboarding-feature-\(tutorial.rawValue)"
                )

            VStack(alignment: .leading, spacing: 10) {
                Text(tutorial.title)
                    .font(BrowserOnboardingTypography.display(40))
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text(tutorial.detail)
                    .font(
                        BrowserOnboardingTypography.sans(16, weight: .medium)
                    )
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                ForEach(tutorial.features) { feature in
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BrowserOnboardingPalette.coral)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title)
                                .font(
                                    BrowserOnboardingTypography.sans(
                                        14,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(BrowserOnboardingPalette.ink)
                            Text(feature.detail)
                                .font(
                                    BrowserOnboardingTypography.sans(
                                        12,
                                        weight: .medium
                                    )
                                )
                                .foregroundStyle(
                                    BrowserOnboardingPalette.inkSoft
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer()
        }
    }
}

#Preview("Tutorial Copy") {
    BrowserMacOnboardingTutorialCopy(tutorial: .spaces)
        .padding(48)
        .frame(width: 440, height: 540)
        .background(BrowserOnboardingPalette.paper)
}
