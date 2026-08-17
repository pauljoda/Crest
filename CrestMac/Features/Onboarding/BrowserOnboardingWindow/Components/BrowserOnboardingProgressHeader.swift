import SwiftUI

struct BrowserOnboardingProgressHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let step: BrowserOnboardingStep

    private var progressIndex: Int {
        switch step {
        case .welcome, .featureSpaces, .featureTabs, .featureSync:
            0
        case .importBrowser:
            1
        case .review, .manualSetup, .complete:
            2
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            CrestStartPageMark()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text("Crest Setup")
                .font(BrowserOnboardingTypography.sans(14, weight: .bold))
                .foregroundStyle(CrestBrandPalette.paper)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { item in
                    Capsule()
                        .fill(
                            item <= progressIndex
                                ? BrowserOnboardingPalette.butter
                                : CrestBrandPalette.paper.opacity(0.22)
                        )
                        .frame(width: item == progressIndex ? 34 : 16, height: 6)
                        .animation(
                            motion(CrestMotion.onboardingProgress),
                            value: step
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup progress")
            .accessibilityValue("Step \(progressIndex + 1) of 3")
        }
        .padding(.horizontal, 22)
        .frame(height: 56)
        .background(CrestBrandPalette.ink)
    }

    private func motion(_ animation: Animation) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}
