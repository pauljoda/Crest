import SwiftUI

struct BrowserExternalLinkDestinationSection: View {
    @Binding var destination: ExternalLinkDestination
    @Binding var spaceID: UUID?
    let spaces: [SpaceModel]
    /// Absent where apps don't take a full-screen Space of their own.
    var opensOverFullScreenApps: Binding<Bool>? = nil

    var body: some View {
        Section("Links from other apps") {
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

            if destination.opensQuickWindow, let opensOverFullScreenApps {
                Toggle("Open over full-screen apps", isOn: opensOverFullScreenApps)
                    .accessibilityIdentifier("quick-window-over-full-screen-toggle")
            }
        }
    }
}
