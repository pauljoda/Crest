import SwiftUI

struct MobileOnboardingSpaceCard: View {
    let previewSpace: BrowserSpace
    @Binding var name: String
    let canRemove: Bool
    let customize: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(spacing: MobileOnboardingLayout.spaceCardSpacing) {
            BrowserSpaceSidebarPreview(space: previewSpace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(
                    BrowserMobileAccessibilityID.spacePreview(
                        previewSpace.id
                    )
                )
                .overlay(alignment: .top) {
                    MobileOnboardingSpaceCardActions(
                        spaceID: previewSpace.id,
                        canRemove: canRemove,
                        customize: customize,
                        remove: remove
                    )
                    .padding(MobileOnboardingLayout.spaceCardOverlayPadding)
                }

            TextField("Space name", text: $name)
                .font(.headline)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .accessibilityLabel("Space name")
                .accessibilityIdentifier(
                    BrowserManualSetupAccessibilityID.spaceName(
                        previewSpace.id
                    )
                )
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("Onboarding Space Card", traits: .fixedLayout(width: 340, height: 500)) {
    @Previewable @State var name = "Work"
    let fixture = MobileBrowserPreviewFixture()
    MobileOnboardingSpaceCard(
        previewSpace: fixture.space,
        name: $name,
        canRemove: true,
        customize: {},
        remove: {}
    )
    .padding()
}
