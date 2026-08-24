import SwiftUI

/// The folder as one thing: its header, the rows it holds, the menu that acts
/// on it, and the two presentations that menu can raise.
struct BrowserSavedFolderGroupSurface: View {
    let configuration: BrowserSavedFolderGroupConfiguration
    let interaction: BrowserSavedFolderGroupInteractionContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folder: SavedFolder { configuration.folder }

    private var dragItem: BrowserFolderDragItem {
        BrowserFolderDragItem(
            folderID: folder.id,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserSavedFolderHeader(
                configuration: configuration,
                interaction: interaction
            )

            BrowserSavedFolderTabRows(
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
            // A long press opens this menu out of the same gesture that would
            // otherwise lift the folder. Telling the drag state the menu has
            // the press is what keeps the two from both claiming it.
            .onAppear {
                configuration.browser.folderDragState.contextMenuDidOpen(
                    for: dragItem
                )
                // And the reorder state, which is where a touch lift lives and
                // which no drag session will report back to once the menu has
                // the press. See `yieldToCompetingInteraction`.
                configuration.browser.sidebarReorderState
                    .yieldToCompetingInteraction()
            }
            .onDisappear {
                configuration.browser.folderDragState.contextMenuDidClose(
                    for: dragItem
                )
            }
        }
        .popover(
            isPresented: interaction.isChoosingColor,
            arrowEdge: .trailing
        ) {
            BrowserFolderColorPicker(color: interaction.folderColor)
                .presentationCompactAdaptation(.popover)
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
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.collection,
                reduceMotion: reduceMotion
            ),
            value: configuration.tabs.map(\.id)
        )
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
        .onChange(of: configuration.selectedTabID) { _, selectedTabID in
            interaction.collapsedTabVisibility.wrappedValue.selectionDidChange(
                isExpanded: interaction.isExpanded.wrappedValue,
                selectedTabID: selectedTabID,
                folderTabIDs: configuration.tabs.map(\.id)
            )
        }
        .onChange(of: configuration.residencyRevision, initial: true) { _, _ in
            interaction.collapsedTabVisibility.wrappedValue.residencyDidChange(
                isExpanded: interaction.isExpanded.wrappedValue,
                selectedTabID: configuration.selectedTabID,
                residentFolderTabIDs: configuration.residentFolderTabIDs
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
