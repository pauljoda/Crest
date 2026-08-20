import SwiftUI

/// The folder header's content: the disclosure button a reader opens the
/// folder with, or the field they are renaming it in.
///
/// Renaming happens in place, where the title already is, so the row keeps its
/// icon and its shape and only the text becomes editable. Return commits,
/// Escape abandons the edit, and losing focus commits — the group owns the
/// focus so that last rule has one place to live.
struct BrowserSavedFolderHeaderControl: View {
    let configuration: BrowserSavedFolderGroupConfiguration
    let interaction: BrowserSavedFolderGroupInteractionContext

    private var folder: SavedFolder { configuration.folder }

    private var isEditing: Bool {
        interaction.editingFolderRequest.wrappedValue
            == configuration.folderRuntimeAssignment
    }

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 7) {
                    BrowserSavedFolderIcon(
                        folder: folder,
                        isExpanded: interaction.isExpanded.wrappedValue,
                        metrics: configuration.headerMetrics
                    )

                    TextField("Folder Name", text: interaction.draftTitle)
                        .textFieldStyle(.plain)
                        .focused(interaction.isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit(interaction.commitTitle)
                        .onKeyPress(.escape) {
                            interaction.cancelTitleEditing()
                            return .handled
                        }

                    Spacer(minLength: 8)
                }
                .browserSavedFolderHeaderLayout(configuration: configuration)
            } else {
                Button(action: interaction.toggleExpansion) {
                    HStack(spacing: 7) {
                        BrowserSavedFolderIcon(
                            folder: folder,
                            isExpanded: interaction.isExpanded.wrappedValue,
                            metrics: configuration.headerMetrics
                        )

                        Text(folder.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }
                    .browserSavedFolderHeaderLayout(configuration: configuration)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
