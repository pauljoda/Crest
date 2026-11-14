import SwiftUI

/// The folder as one thing: its header, the rows it holds, the menu that acts
/// on it, and the two presentations that menu can raise.
///
/// Where a finger holds the folder while folder previews are on, the
/// folder's card opens in place of the system's menu, as a Peek opens in
/// place of a held link's, and offers the menu behind "…". The folder still
/// lifts as the hold begins, so a hold that moves drags it, and the drag takes
/// the card down. VoiceOver keeps the system's menu.
struct BrowserFolderGroupSurface: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.browserTabPreviewState) private var previewOverride
    @State private var headerFrame = BrowserFolderHeaderFrame()

    private var folder: FolderStateModel { configuration.folder }

    private var dragItem: BrowserFolderDragItem { configuration.dragItem }

    /// The preview the folder's card shows in.
    private var preview: BrowserTabPreviewState { previewOverride ?? sidebarInteraction.tabPreview }

    /// Whether a hold opens the folder's card in place of the system's menu.
    private var holdOpensCard: Bool {
        configuration.capabilities.supportsTouch && configuration.capabilities.supportsOrganization
            && !voiceOverEnabled && BrowserDeviceAppearanceStore.shared.previewsFoldersOnHover && preview.isHosted
    }

    var body: some View {
        BrowserFolderHeader(
            configuration: configuration,
            interaction: interaction
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            headerFrame.value = frame
        }
        .modifier(
            BrowserFolderMenuOrCard(opensCard: holdOpensCard, hold: showCardForHold) {
                if configuration.capabilities.supportsOrganization {
                    organizationMenu
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
        )
        .onChange(of: presentsFromHeader) { _, presents in
            if presents { dismissHeldCard() }
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
            dismissHeldCard()
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

    /// The folder's menu, in the system's menu or behind its card's "…".
    private var organizationMenu: BrowserFolderOrganizationMenu {
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
    }

    /// Whether the header shows one of the presentations its menu raises,
    /// which a held card makes room for.
    private var presentsFromHeader: Bool {
        interaction.isChoosingColor.wrappedValue || interaction.isChoosingIcon.wrappedValue
            || interaction.isConfirmingDeletion.wrappedValue
    }

    /// Opens the folder's card where a finger held the folder.
    private func showCardForHold() {
        guard holdOpensCard, let frame = headerFrame.value else { return }
        preview.hold(
            BrowserTabPreviewTarget(
                subject: .folder(folder), context: configuration.context, frame: frame, isHeldByTouch: true,
                folderMenu: organizationMenu))
    }

    /// Takes down the folder's held card, as when its menu renames the folder
    /// or raises a presentation from the header.
    private func dismissHeldCard() {
        guard let shown = preview.shown, shown.isHeldByTouch, shown.key.item == .folder(folder.id) else { return }
        preview.dismiss()
    }
}

/// The folder's menu, or, where a hold opens the folder's card instead, the
/// hold that opens it.
private struct BrowserFolderMenuOrCard<MenuItems: View>: ViewModifier {
    let opensCard: Bool
    let hold: () -> Void
    @ViewBuilder let menuItems: () -> MenuItems

    func body(content: Content) -> some View {
        if opensCard {
            content.modifier(BrowserPlatformHoldRecognizer(hold: hold))
        } else {
            content.contextMenu(menuItems: menuItems)
        }
    }
}

/// Where a folder's header last sat in the window, kept where reading it
/// redraws nothing.
private final class BrowserFolderHeaderFrame {
    var value: CGRect?
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
