import SwiftUI

struct MobileOnboardingSpaceSetupPage: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?

    let existingSession: BrowserSession
    let horizontalSizeClass: UserInterfaceSizeClass?
    let errorMessage: String?
    let secondaryTitle: String
    let secondaryAction: () -> Void
    let finish: () -> Void
    let addSpace: () -> Void
    let customize: (SpaceID) -> Void
    let remove: (SpaceID) -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: 3,
            primaryTitle: "Finish Setup",
            primarySystemImage: "checkmark",
            primaryIdentifier:
                BrowserMobileAccessibilityID.manualSetupFinish,
            secondaryTitle: secondaryTitle,
            secondaryIdentifier:
                BrowserMobileAccessibilityID.back,
            secondaryAction: secondaryAction,
            primaryAction: finish,
            scrolls: false
        ) {
            VStack(spacing: MobileOnboardingLayout.setupSpacing) {
                MobileOnboardingTitle(
                    title: "Build your Spaces",
                    detail: "Name each Space now. Add tabs once you are inside Crest."
                )

                MobileOnboardingSpaceCarousel(
                    plan: $plan,
                    selectedSpaceID: $selectedSpaceID,
                    existingSession: existingSession,
                    horizontalSizeClass: horizontalSizeClass,
                    addSpace: addSpace,
                    customize: customize,
                    remove: remove
                )

                Text("Swipe to review each Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(
                        BrowserManualSetupAccessibilityID.error
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
