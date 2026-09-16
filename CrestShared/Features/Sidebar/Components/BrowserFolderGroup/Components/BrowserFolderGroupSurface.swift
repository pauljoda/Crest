import SwiftUI

/// The folder as one thing: its header, the rows it holds, the menu that acts
/// on it, and the two presentations that menu can raise.
struct BrowserFolderGroupSurface: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext
    var showsExpandedRows = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folder: BrowserFolder { configuration.folder }

    private var dragItem: BrowserFolderDragItem {
        BrowserFolderDragItem(
            folderID: folder.id,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID,
            memberTabIDs: configuration.subtreeTabIDs
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserFolderHeader(
                configuration: configuration,
                interaction: interaction
            )

            if showsExpandedRows || !interaction.isExpanded.wrappedValue {
                BrowserFolderTabRows(configuration: configuration, interaction: interaction)
            }
        }
        .contextMenu {
            if configuration.capabilities.supportsOrganization {
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
        .popover(
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
                currentEmoji: BrowserIconSymbol.emoji(from: folder.symbol),
                currentSystemSymbol: BrowserIconSymbol.emoji(from: folder.symbol) == nil ? folder.symbol : nil,
                showsReset: folder.symbol != "folder" && folder.symbol != "folder.fill",
                resetTitle: "Use Folder Icon",
                setEmoji: { interaction.folderSymbol.wrappedValue = BrowserIconSymbol.symbol(forEmoji: $0) },
                setSystemSymbol: { interaction.folderSymbol.wrappedValue = $0 },
                reset: { interaction.folderSymbol.wrappedValue = "folder" }
            )
        )
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
            Text("Its tabs stay in this section, and any nested folders move up one level.")
        }
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.collection,
                reduceMotion: reduceMotion
            ),
            value: configuration.tabs.map(\.id)
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
                .onChange(of: configuration.selectedTabID) { _, _ in reconcileVisibility() }
                .onChange(of: configuration.residencyRevision, initial: true) { _, _ in reconcileVisibility() }
        #else
            content
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
        #endif
    }

    #if os(macOS)
        private func reconcileVisibility() {
            guard let space = configuration.browser.space(matching: configuration.assignment),
                !configuration.spaceAccess.isLocked(space),
                let folder = space.folders.first(where: { $0.id == configuration.folder.id })
            else { return }
            let tabs = space.tabSections.tabs(in: folder.id)
            configuration.sidebarInteraction.reconcileCollapsedFolder(
                configuration.folderRuntimeAssignment, isExpanded: !folder.isCollapsed,
                selectedTabID: space.selectedTabID, folderTabIDs: tabs.map(\.id),
                residentFolderTabIDs: tabs.compactMap { tab in
                    configuration.pageAccess.containsResidentPageMatching(
                        BrowserTabRuntimeAssignment(
                            tabID: tab.id, spaceID: space.id, profileID: space.profile.id)) ? tab.id : nil
                })
        }
    #endif
}
