import SwiftUI

/// The folder as one thing: its header, the rows it holds, the menu that acts
/// on it, and the two presentations that menu can raise.
struct BrowserFolderGroupSurface: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folder: FolderStateModel { configuration.folder }

    private var dragItem: BrowserFolderDragItem { configuration.dragItem }

    var body: some View {
        BrowserFolderHeader(
            configuration: configuration,
            interaction: interaction
        )
        .contextMenu {
            if configuration.capabilities.supportsOrganization {
                BrowserFolderOrganizationMenu(
                    folder: folder,
                    context: configuration.context,
                    assignment: configuration.folderRuntimeAssignment,
                    createNestedFolder: interaction.beginCreatingChild,
                    renameFolder: interaction.beginRenaming,
                    changeColor: {
                        interaction.isChoosingColor.wrappedValue = true
                    },
                    changeIcon: {
                        interaction.isChoosingIcon.wrappedValue = true
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
                    sidebarInteraction.folderDragState.contextMenuDidOpen(
                        for: dragItem
                    )
                    // And the reorder state, which is where a touch lift lives and
                    // which no drag session will report back to once the menu has
                    // the press. See `yieldToCompetingInteraction`.
                    sidebarInteraction.sidebarReorderState
                        .yieldToCompetingInteraction()
                }
                .onDisappear {
                    sidebarInteraction.folderDragState.contextMenuDidClose(
                        for: dragItem
                    )
                }
            }
        }
        .crestPopover(
            isPresented: interaction.isChoosingColor,
            arrowEdge: .trailing
        ) {
            BrowserFolderColorPicker(color: interaction.folderColor)
                .presentationCompactAdaptation(.popover)
        }
        .browserIconCustomizationPopover(
            BrowserIconCustomizationPresentation(
                isPresented: interaction.isChoosingIcon,
                title: "Folder Icon",
                currentEmoji: BrowserIconSymbol.emoji(from: folder.displaySymbol),
                currentSystemSymbol: BrowserIconSymbol.emoji(from: folder.displaySymbol) == nil
                    ? folder.displaySymbol : nil,
                showsReset: folder.displaySymbol != "folder" && folder.displaySymbol != "folder.fill",
                resetTitle: "Use Folder Icon",
                setEmoji: { interaction.folderSymbol.wrappedValue = BrowserIconSymbol.symbol(forEmoji: $0) },
                setSystemSymbol: { interaction.folderSymbol.wrappedValue = $0 },
                reset: { interaction.folderSymbol.wrappedValue = "folder" }
            )
        )
        .confirmationDialog(
            "Delete \(folder.shownTitle)?",
            isPresented: interaction.isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                interaction.deleteFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            BrowserFolderDeletionMessage(folder: folder, space: configuration.context.space)
        }
        .animation(
            CrestMotion.collection.unlessReducingMotion(reduceMotion),
            value: folder.isCollapsed
        )
        .onAppear(perform: interaction.beginTitleEditingIfNeeded)
        .modifier(BrowserFolderCollapsedVisibilityUpdates(configuration: configuration, interaction: interaction))
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

/// macOS keeps visibility in the retained Space host; mobile retains its
/// existing row-local lifecycle. A lazy Mac row remount must not reset history.
private struct BrowserFolderCollapsedVisibilityUpdates: ViewModifier {
    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    func body(content: Content) -> some View {
        #if os(macOS)
            content
                // Also supports isolated folder components in previews and
                // practice surfaces. Reconciliation is idempotent on remount;
                // the retained host updates folders while these views are absent.
                .onChange(of: interaction.isExpanded.wrappedValue, initial: true) { _, _ in reconcileVisibility() }
                .onChange(of: configuration.shownFolderTabID) { _, _ in reconcileVisibility() }
                .onChange(of: configuration.residencyRevision, initial: true) { _, _ in reconcileVisibility() }
        #else
            content
                .onChange(
                    of: interaction.isExpanded.wrappedValue,
                    initial: true
                ) { _, isExpanded in
                    interaction.collapsedTabVisibility.wrappedValue.expansionDidChange(
                        isExpanded: isExpanded,
                        selectedTabID: configuration.shownFolderTabID,
                        folderTabIDs: configuration.folderTabIDs,
                        residentFolderTabIDs: configuration.residentFolderTabIDs
                    )
                }
                .onChange(of: configuration.shownFolderTabID) { _, selectedTabID in
                    interaction.collapsedTabVisibility.wrappedValue.selectionDidChange(
                        isExpanded: interaction.isExpanded.wrappedValue,
                        selectedTabID: selectedTabID,
                        folderTabIDs: configuration.folderTabIDs
                    )
                }
                .onChange(of: configuration.residencyRevision, initial: true) { _, _ in
                    interaction.collapsedTabVisibility.wrappedValue.residencyDidChange(
                        isExpanded: interaction.isExpanded.wrappedValue,
                        residentFolderTabIDs: configuration.residentFolderTabIDs
                    )
                }
        #endif
    }

    #if os(macOS)
        private func reconcileVisibility() {
            guard configuration.context.space.folders.contains(configuration.folder.id),
                !configuration.spaceAccess.isLocked(configuration.context.space)
            else { return }
            configuration.sidebarInteraction.reconcileCollapsedFolder(
                configuration.folderRuntimeAssignment, isExpanded: !configuration.folder.isCollapsed,
                selectedTabID: configuration.shownFolderTabID, folderTabIDs: configuration.folderTabIDs,
                residentFolderTabIDs: configuration.residentFolderTabIDs)
        }
    #endif
}

/// What deleting a folder takes with it: every tab and folder inside it,
/// however deep, with the tabs kept in the Archive.
private struct BrowserFolderDeletionMessage: View {
    let folder: FolderStateModel
    let space: SpaceModel

    var body: some View {
        let tabs = space.tabIDs(inFolder: folder.id).count
        let folders = space.folderChoices(inside: folder.id).count
        switch (tabs, folders) {
        case (0, 0):
            Text("The folder is empty.")
        case (_, 0):
            Text("This also deletes the ^[\(tabs) tab](inflect: true) inside it. Deleted tabs go to the Archive.")
        case (0, _):
            Text("This also deletes the ^[\(folders) empty folder](inflect: true) inside it.")
        default:
            Text(
                "This also deletes everything inside it: ^[\(tabs) tab](inflect: true) and ^[\(folders) folder](inflect: true). Deleted tabs go to the Archive."
            )
        }
    }
}
