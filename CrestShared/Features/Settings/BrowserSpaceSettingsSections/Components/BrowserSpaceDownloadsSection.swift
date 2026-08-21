import SwiftUI

/// Where one Space's downloads land.
///
/// Rendered only for a shell that passed a ``BrowserSpaceDownloadSettings``,
/// which is the same thing as saying only for a shell with a folder chooser to
/// open. Everything that touches the file system stays behind that value's two
/// closures.
struct BrowserSpaceDownloadsSection: View {
    let settings: BrowserSpaceDownloadSettings

    var body: some View {
        Section("Downloads") {
            Toggle(
                "Ask where to save each download",
                isOn: settings.asksWhereToSave
            )
            .accessibilityIdentifier("space-download-save-panel")

            LabeledContent("Download location") {
                Text(settings.directoryName)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Choose Folder…", systemImage: "folder") {
                    settings.chooseDirectory()
                }
                Button("Use Downloads", systemImage: "arrow.uturn.backward") {
                    settings.resetDirectory()
                }
                .disabled(!settings.usesCustomDirectory)
            }

            if let errorMessage = settings.errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.red)
            }

            Text(settings.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
