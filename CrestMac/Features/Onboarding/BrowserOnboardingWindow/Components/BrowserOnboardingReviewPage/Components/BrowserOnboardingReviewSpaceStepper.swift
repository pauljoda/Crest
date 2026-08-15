import SwiftUI

struct BrowserOnboardingReviewSpaceStepper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let spaces: [BrowserImportSpaceReview]
    let selectedSpaceID: SpaceID?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(BrowserOnboardingPalette.line)
                .frame(width: 1)
            VStack(spacing: 12) {
                ForEach(spaces) { item in
                    let isCurrent = item.id == selectedSpaceID
                    Capsule(style: .continuous)
                        .fill(
                            isCurrent
                                ? BrowserOnboardingPalette.coral
                                : BrowserOnboardingPalette.inkSoft.opacity(0.34)
                        )
                        .frame(
                            width: isCurrent ? 10 : 7,
                            height: isCurrent ? 34 : 7
                        )
                        .animation(
                            motion(CrestMotion.onboardingProgress),
                            value: selectedSpaceID
                        )
                        .accessibilityLabel(item.sourceSpace.name)
                        .accessibilityValue(
                            isCurrent ? "Current Space" : "Space in review"
                        )
                }
            }
            .padding(.vertical, 10)
            .background(BrowserOnboardingPalette.parchment)
        }
        .fixedSize()
        .padding(.trailing, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space review progress")
    }

    private func motion(_ animation: Animation) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}

#Preview("Review Space Progress") {
    let plan = BrowserOnboardingWindowPreviewFixture.reviewPlan
    BrowserOnboardingReviewSpaceStepper(
        spaces: plan.spaces,
        selectedSpaceID: plan.spaces.first?.id
    )
    .frame(height: 240)
    .background(BrowserOnboardingPalette.parchment)
}
