import SwiftUI

/// The look the Spaces setup makes wear, as a preview button for each style.
/// Choosing one restyles the Spaces setup makes, and going on gives Crest's
/// customization that style.
struct MobileOnboardingLookPage: View {
    let look: SetupLook
    let choose: (SetupLook) -> Void
    /// Makes the chosen look's style the one Crest's customization shows.
    let adoptStyle: (BrowserCustomizationStyle) -> Void
    let back: () -> Void
    let continueSetup: () -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: nil,
            primaryTitle: "Continue",
            primarySystemImage: "chevron.right",
            primaryIdentifier: "onboarding-look-continue",
            secondaryTitle: String(localized: "Back"),
            secondaryIdentifier: BrowserMobileAccessibilityID.close,
            secondaryAction: back,
            primaryAction: continueWithLook,
            scrolls: false
        ) {
            VStack(spacing: MobileOnboardingLookMetrics.titleSpacing) {
                Text("Pick your look")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                // The three fit the page without scrolling, down to the
                // smallest face; a page too short even for that scrolls.
                GeometryReader { geometry in
                    ScrollView {
                        BrowserCustomizationStyleChoices(
                            selection: .matching(look), spaceIcons: nil, faceSize: faceSize(fitting: geometry.size),
                            axis: .vertical
                        ) { style in
                            choose(style.look)
                        }
                        .frame(width: geometry.size.width)
                        .frame(minHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onboarding-look")
            }
        }
    }

    /// The face that stacks three, each with its title, down `size`, no
    /// larger than an iPad shows.
    private func faceSize(fitting size: CGSize) -> CGFloat {
        let items = CGFloat(BrowserCustomizationStyle.all.count)
        let room =
            size.height - 2 * CrestSpacing.medium - (items - 1) * BrowserCustomizationStyleMetrics.spacing
            - items * MobileOnboardingLookMetrics.titleRoom
        return max(
            MobileOnboardingLookMetrics.smallestFace,
            min(MobileOnboardingLookMetrics.largestFace, room / items, size.width))
    }

    /// Goes on, giving Crest's customization the style of the chosen look.
    private func continueWithLook() {
        adoptStyle(.matching(look))
        continueSetup()
    }
}

private enum MobileOnboardingLookMetrics {
    static let titleSpacing: CGFloat = 12
    /// The room under each face for its title.
    static let titleRoom: CGFloat = 32
    static let smallestFace: CGFloat = 72
    static let largestFace: CGFloat = 220
}

#if DEBUG
    #Preview("Component") {
        @Previewable @State var look = SetupLook.heraldic
        MobileOnboardingLookPage(look: look, choose: { look = $0 }, adoptStyle: { _ in }, back: {}, continueSetup: {})
            .frame(width: 390, height: 844)
    }
#endif
