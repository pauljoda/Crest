import SwiftUI

struct SavedFolderHeaderControl: View {
    let configuration: SavedFolderGroupConfiguration
    let interaction: SavedFolderGroupInteractionContext

    private var folder: SavedFolder { configuration.folder }

    var body: some View {
        Group {
            if interaction.editingFolderRequest.wrappedValue
                == configuration.folderRuntimeAssignment
            {
                HStack(spacing: 7) {
                    SavedFolderIcon(
                        folder: folder,
                        isExpanded: interaction.isExpanded.wrappedValue
                    )

                    TextField("Folder Name", text: interaction.draftTitle)
                        .textFieldStyle(.plain)
                        .focused(interaction.isTitleFocused)
                        .onSubmit(interaction.commitTitle)
                        .onExitCommand(perform: interaction.cancelTitleEditing)

                    Spacer(minLength: 8)
                }
                .savedFolderHeaderLayout(depth: configuration.node.depth)
            } else {
                Button(action: interaction.toggleExpansion) {
                    HStack(spacing: 7) {
                        SavedFolderIcon(
                            folder: folder,
                            isExpanded: interaction.isExpanded.wrappedValue
                        )

                        Text(folder.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }
                    .savedFolderHeaderLayout(depth: configuration.node.depth)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("Saved Folder Rename Control") {
    @Previewable @State var isExpanded = true
    @Previewable @State var editingFolderRequest: BrowserFolderRuntimeAssignment? =
        BrowserFolderRuntimeAssignment(
            folderID: SavedFolderGroupPreviewFixture.folderID,
            spaceID: SavedFolderGroupPreviewFixture.spaceID,
            profileID: SavedFolderGroupPreviewFixture.profileID
        )
    @Previewable @State var draftTitle = "Research"
    @Previewable @State var visibility =
        BrowserCollapsedFolderTabVisibilityState()
    @Previewable @FocusState var isTitleFocused: Bool

    let configuration = SavedFolderGroupPreviewFixture.configuration()
    SavedFolderHeaderControl(
        configuration: configuration,
        interaction: SavedFolderGroupPreviewFixture.interaction(
            isExpanded: $isExpanded,
            editingFolderRequest: $editingFolderRequest,
            draftTitle: $draftTitle,
            collapsedTabVisibility: $visibility,
            isTitleFocused: $isTitleFocused
        )
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
}
