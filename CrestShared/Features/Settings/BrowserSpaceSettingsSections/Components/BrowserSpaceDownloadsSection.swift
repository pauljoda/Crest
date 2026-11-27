import SwiftUI

/// Where one Space's downloads land.
///
/// Rendered only for a shell that passed a ``BrowserSpaceDownloadSettings``,
/// which is the same thing as saying only for a shell with a folder chooser to
/// open. Everything that touches the file system stays behind that value's two
/// closures.
struct BrowserSpaceDownloadsSection: View {
    let settings: BrowserSpaceDownloadSettings

    @Environment(\.browserInteractionCapabilities) private var capabilities

    var body: some View {
        Section("Downloads") {
            if let asksWhereToSave = settings.asksWhereToSave {
                Toggle("Ask where to save each download", isOn: asksWhereToSave)
                    .accessibilityIdentifier("space-download-save-panel")
            }

            LabeledContent("Download location") {
                Text(settings.directoryName)
                    .foregroundStyle(.secondary)
            }

            // A touch form row takes every tap in it, so each button keeps a
            // row of its own there.
            if capabilities.supportsTouch {
                folderButtons
            } else {
                HStack { folderButtons }
            }

            if let errorMessage = settings.errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(CrestColor.danger)
            }
        }
    }

    @ViewBuilder
    private var folderButtons: some View {
        Button("Choose Folder…") { settings.chooseDirectory() }
            .accessibilityIdentifier("space-download-choose-folder")
        Button(settings.resetTitle) { settings.resetDirectory() }
            .disabled(!settings.usesCustomDirectory)
            .accessibilityIdentifier("space-download-reset-folder")
    }
}
