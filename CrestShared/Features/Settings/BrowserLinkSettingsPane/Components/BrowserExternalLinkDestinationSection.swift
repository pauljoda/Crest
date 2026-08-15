import SwiftUI

struct BrowserExternalLinkDestinationSection: View {
    @Binding var destination: BrowserExternalLinkDestination
    @Binding var spaceID: SpaceID?
    let spaces: [BrowserSpace]

    var body: some View {
        Section("Links from other apps") {
            Picker("Open in", selection: $destination) {
                ForEach(BrowserExternalLinkDestination.allCases) { destination in
                    Text(destination.title).tag(destination)
                }
            }
            .accessibilityIdentifier("external-link-destination")

            if destination == .chosenSpace {
                CrestSpaceMenuPicker(
                    "Space",
                    selection: $spaceID,
                    spaces: CrestSpaceIdentity.list(spaces)
                )
            }

            BrowserPlatformLinkSettingsGuidance(kind: .externalDestination)
        }
    }
}

#Preview("External Link Destination") {
    @Previewable @State var destination = BrowserExternalLinkDestination.chosenSpace
    @Previewable @State var spaceID: SpaceID? =
        BrowserLinkSettingsPreviewFixture().secondarySpace.id
    let fixture = BrowserLinkSettingsPreviewFixture()
    Form {
        BrowserExternalLinkDestinationSection(
            destination: $destination,
            spaceID: $spaceID,
            spaces: fixture.browser.session.spaces
        )
    }
    .formStyle(.grouped)
}
