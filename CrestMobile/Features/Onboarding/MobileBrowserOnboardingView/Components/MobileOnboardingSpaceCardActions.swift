import SwiftUI

struct MobileOnboardingSpaceCardActions: View {
    let spaceID: SpaceID
    let canRemove: Bool
    let customize: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            if canRemove {
                Button(
                    "Remove Space",
                    systemImage: "trash",
                    role: .destructive,
                    action: remove
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .background(.regularMaterial, in: .circle)
                .accessibilityIdentifier(
                    BrowserMobileAccessibilityID.removeSpace(
                        spaceID
                    )
                )
            }

            Spacer(minLength: 0)

            Button(
                "Customize Space",
                systemImage: "paintbrush",
                action: customize
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .background(.regularMaterial, in: .circle)
            .accessibilityIdentifier(
                BrowserMobileAccessibilityID.customizeSpace(
                    spaceID
                )
            )
        }
    }
}

#Preview("Onboarding Space Card Actions") {
    let fixture = MobileBrowserPreviewFixture()
    MobileOnboardingSpaceCardActions(
        spaceID: fixture.space.id,
        canRemove: true,
        customize: {},
        remove: {}
    )
    .padding()
}
