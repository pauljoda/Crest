import SwiftUI

struct SavedFolderGroupSurface: View {
    let configuration: SavedFolderGroupConfiguration
    let interaction: SavedFolderGroupInteractionContext

    private var folder: SavedFolder { configuration.folder }

    var body: some View {
        VStack(spacing: 0) {
            SavedFolderHeader(
                configuration: configuration,
                interaction: interaction
            )

            SavedFolderTabRows(
                configuration: configuration,
                interaction: interaction
            )
        }
        .contextMenu {
            BrowserFolderOrganizationMenu(
                folder: folder,
                assignment: configuration.folderRuntimeAssignment,
                browser: configuration.browser,
                spaceAccess: configuration.spaceAccess,
                createNestedFolder: interaction.beginCreatingChild,
                renameFolder: interaction.beginRenaming,
                changeColor: {
                    interaction.isChoosingColor.wrappedValue = true
                },
                deleteFolder: {
                    interaction.isConfirmingDeletion.wrappedValue = true
                }
            )
            .tint(.primary)
        }
        .popover(
            isPresented: interaction.isChoosingColor,
            arrowEdge: .trailing
        ) {
            BrowserFolderColorPicker(color: interaction.folderColor)
        }
        .confirmationDialog(
            "Delete \(folder.title)?",
            isPresented: interaction.isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                interaction.deleteFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its tabs stay saved, and any nested folders move up one level.")
        }
        .onAppear(perform: interaction.beginTitleEditingIfNeeded)
        .onChange(
            of: interaction.isExpanded.wrappedValue,
            initial: true
        ) { _, isExpanded in
            interaction.collapsedTabVisibility.wrappedValue.expansionDidChange(
                isExpanded: isExpanded,
                selectedTabID: configuration.selectedTabID,
                folderTabIDs: configuration.tabs.map(\.id)
            )
        }
        .onChange(of: interaction.editingFolderRequest.wrappedValue) { _, _ in
            interaction.beginTitleEditingIfNeeded()
        }
        .onChange(of: interaction.isTitleFocused.wrappedValue) { _, focused in
            if !focused,
                interaction.editingFolderRequest.wrappedValue
                    == configuration.folderRuntimeAssignment
            {
                interaction.commitTitle()
            }
        }
    }
}

#Preview("Saved Folder Surface") {
    @Previewable @State var isExpanded = true
    @Previewable @State var editingFolderRequest: BrowserFolderRuntimeAssignment? = nil
    @Previewable @State var isDropTargeted = false
    @Previewable @State var draftTitle = "Research"
    @Previewable @State var isChoosingColor = false
    @Previewable @State var isConfirmingDeletion = false
    @Previewable @State var visibility =
        BrowserCollapsedFolderTabVisibilityState()
    @Previewable @FocusState var isTitleFocused: Bool

    let configuration = SavedFolderGroupPreviewFixture.configuration()
    SavedFolderGroupSurface(
        configuration: configuration,
        interaction: SavedFolderGroupPreviewFixture.interaction(
            isExpanded: $isExpanded,
            editingFolderRequest: $editingFolderRequest,
            isDropTargeted: $isDropTargeted,
            draftTitle: $draftTitle,
            isChoosingColor: $isChoosingColor,
            isConfirmingDeletion: $isConfirmingDeletion,
            collapsedTabVisibility: $visibility,
            isTitleFocused: $isTitleFocused
        )
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
}
