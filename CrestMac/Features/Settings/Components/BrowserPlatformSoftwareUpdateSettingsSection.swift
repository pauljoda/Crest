import SwiftUI

struct BrowserPlatformSoftwareUpdateSettingsSection: View {
    @Environment(BrowserSoftwareUpdateService.self) private var softwareUpdates

    var body: some View {
        Section("Software updates") {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { softwareUpdates.automaticallyChecksForUpdates },
                    set: softwareUpdates.setAutomaticallyChecksForUpdates
                )
            )

            Toggle(
                "Download and install updates automatically",
                isOn: Binding(
                    get: { softwareUpdates.automaticallyDownloadsUpdates },
                    set: softwareUpdates.setAutomaticallyDownloadsUpdates
                )
            )
            .disabled(!softwareUpdates.automaticallyChecksForUpdates)

            Picker(
                "Update channel",
                selection: Binding(
                    get: { softwareUpdates.channel },
                    set: { softwareUpdates.channel = $0 }
                )
            ) {
                ForEach(BrowserSoftwareUpdateChannel.allCases) { channel in
                    Text(channel.title).tag(channel)
                }
            }

            Text(softwareUpdates.channel.guidance)
                .crestFormFootnote()

            Button("Check for Updates…") {
                softwareUpdates.checkForUpdates()
            }
            .disabled(!softwareUpdates.isEnabled)

            if let startErrorDescription = softwareUpdates.startErrorDescription {
                Label(
                    startErrorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .crestFormFootnote()
                .foregroundStyle(.orange)
            }
        }
    }
}
