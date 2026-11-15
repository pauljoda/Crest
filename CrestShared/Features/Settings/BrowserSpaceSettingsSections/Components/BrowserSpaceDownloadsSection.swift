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
                Toggle(
                    "Ask where to save each download",
                    isOn: asksWhereToSave
                )
                .accessibilityIdentifier("space-download-save-panel")
            }

            LabeledContent("Download location") {
                Text(settings.directoryName)
                    .foregroundStyle(.secondary)
            }

            if capabilities.supportsTouch {
                // A row of a touch Form fires every button it holds, so each
                // gets its own row.
                chooseButton
                resetButton
            } else {
                HStack {
                    chooseButton
                    resetButton
                }
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

    private var chooseButton: some View {
        Button("Choose Folder…") {
            settings.chooseDirectory()
        }
    }

    private var resetButton: some View {
        Button {
            settings.resetDirectory()
        } label: {
            Text(settings.resetTitle)
        }
        .disabled(!settings.usesCustomDirectory)
    }
}
