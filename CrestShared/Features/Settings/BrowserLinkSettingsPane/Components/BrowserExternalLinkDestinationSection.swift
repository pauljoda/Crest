import SwiftUI

struct BrowserExternalLinkDestinationSection: View {
    @Binding var destination: ExternalLinkDestination
    @Binding var spaceID: SpaceID?
    let spaces: [BrowserSpace]

    var body: some View {
        Section("Links from other apps", systemImage: "link") {
            Picker("Open in", selection: $destination) {
                ForEach(ExternalLinkDestination.all, id: \.self) { destination in
                    Text(destination.title).tag(destination)
                }
            }
            .accessibilityIdentifier("external-link-destination")

            if destination.asksForSpace {
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
