import SwiftUI

/// One saved folder in the sidebar — its header and the rows it holds — on
/// every shell.
///
/// The group owns the state a folder has to keep between events: whether its
/// title is being edited, which deferred action a menu asked for, and which
/// tab a collapsed folder is still showing. Everything a part needs to draw
/// arrives as `BrowserFolderGroupConfiguration`; everything a part may do
/// arrives as `BrowserFolderGroupInteractionContext`.
///
/// A folder's menu actions outlive the menu that asked for them, so each is
/// held as the folder it was asked for rather than as a bare flag, and every
/// one of them is re-checked against the live session before it runs. A Space
/// can be reselected, relocked, or have the folder deleted out from under an
/// open colour popover, and a request that can no longer be honoured is
/// dropped instead of landing on whatever took its place.
struct BrowserFolderGroup: View {
    let node: BrowserFolderNode
    let tree: BrowserFolderTree
    let ordering: BrowserSidebarFolderListItem.Projection
    let tabSections: BrowserTabSections
    private var tabs: [BrowserTab] { tabSections.tabs(in: node.id) }
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let browser: BrowserStore
    let pageAccess: BrowserSidebarPageAccess
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    var promotionNamespace: Namespace.ID? = nil
    var pullNewIcon: ((TabID) -> Void)? = nil
    var restoreSavedLocation: ((TabID) -> Void)? = nil
    /// What opening one of the folder's tabs means to the host. The group
    /// decides *whether* and *which*; the host decides what appears.
    let select: (TabID) -> Void

    @Binding var isExpanded: Bool
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?
    @Environment(\.sidebarSpacePresentation) private var spacePresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftTitle = ""
    @State private var colorRequest: BrowserFolderRuntimeAssignment?
    @State private var deletionRequest: BrowserFolderRuntimeAssignment?
    @State private var collapsedTabVisibility =
        BrowserCollapsedFolderTabVisibilityState()
    @FocusState private var isTitleFocused: Bool

    private var folder: BrowserFolder { node.folder }

    private var configuration: BrowserFolderGroupConfiguration {
        BrowserFolderGroupConfiguration(
            node: node,
            tabs: tabs,
            subtreeTabIDs: subtreeTabIDs,
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: selectedTabID,
            browser: browser,
            pageAccess: pageAccess,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            promotionNamespace: promotionNamespace,
            pullNewIcon: pullNewIcon,
            restoreSavedLocation: restoreSavedLocation,
            select: select,
            spacePresentation: spacePresentation
        )
    }

    private var interaction: BrowserFolderGroupInteractionContext {
        BrowserFolderGroupInteractionContext(
            isExpanded: $isExpanded,
            editingFolderRequest: $editingFolderRequest,
            draftTitle: $draftTitle,
            isChoosingColor: colorPresentation,
            isConfirmingDeletion: deletionPresentation,
            collapsedTabVisibility: $collapsedTabVisibility,
            isTitleFocused: $isTitleFocused,
            folderColor: folderColorBinding,
            beginCreatingChild: beginCreatingChild,
            beginRenaming: beginRenaming,
            toggleExpansion: toggleExpansion,
            beginTitleEditingIfNeeded: beginTitleEditingIfNeeded,
            commitTitle: commitTitle,
            cancelTitleEditing: cancelTitleEditing,
            deleteFolder: deleteFolder,
            unloadKeptCollapsedTab: unloadKeptCollapsedTab
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserFolderGroupSurface(
                configuration: configuration,
                interaction: interaction, showsExpandedRows: false
            )
            if isExpanded {
                folderContents
            }
        }
        .modifier(
            BrowserFolderSectionSurface(
                color: folder.color,
                intensity: configuration.displayBranding?.folderColorIntensity ?? 0,
                textColorMode: configuration.displayBranding?.textColorMode ?? .automatic,
                leadingInset: CrestSpacing.small + CGFloat(node.depth) * BrowserFolderLayout.nestingIndent,
                hasVisibleContents: isExpanded || configuration.keptCollapsedItem(for: collapsedTabVisibility) != nil,
                folderID: folder.id, reorder: browser.sidebarReorderState)
        )
        .modifier(BrowserFolderReorderContainer(configuration: configuration))
        .browserSidebarReorderZone(
            .section(.tabs(placement: folder.location.tabPlacement, folderID: folder.id)),
            state: browser.sidebarReorderState
        )
        .browserSidebarReorderZone(
            .folder(folder.id),
            state: browser.sidebarReorderState,
            isActive: !isExpanded
        )
        .modifier(
            BrowserFolderReorderReservation(configuration: configuration)
        )
        .onChange(of: configuration.folderRuntimeAssignment) { _, _ in
            clearUnavailableDeferredActions()
        }
        .modifier(
            SidebarSpaceRoleCleanupModifier(
                isAvailable: configuration.isAvailableForDisplay,
                hasPendingActions: editingFolderRequest != nil || colorRequest != nil || deletionRequest != nil,
                cancel: clearUnavailableDeferredActions
            )
        )
        .padding(.vertical, BrowserFolderAppearancePolicy.regionInset)
    }

    /// Nested folders are children of the section they move with, so a parent's
    /// measurement, hover surface and lift include the entire expanded subtree.
    @ViewBuilder
    private var folderContents: some View {
        let items = ordering.items(in: folder.id)
        let followingTabIDs = configuration.followingTabIDs
        VStack(spacing: 0) {
            if items.isEmpty {
                BrowserFolderTabRows(configuration: configuration, interaction: interaction, displayedItems: [])
            }
            ForEach(items) { item in
                switch item {
                case .tabs(let row):
                    BrowserFolderTabRows(
                        configuration: configuration, interaction: interaction, displayedItems: [row],
                        followingTabIDsOverride: followingTabIDs)
                case .folder(let childNode):
                    let child = childNode.folder
                    BrowserFolderGroup(
                        node: BrowserFolderNode(
                            folder: child, depth: node.depth + 1,
                            hasChildren: !tree.children(of: child.id).isEmpty),
                        tree: tree, ordering: ordering, tabSections: tabSections,
                        spaceID: spaceID, profileID: profileID, selectedTabID: selectedTabID,
                        browser: browser, pageAccess: pageAccess, spaceAccess: spaceAccess,
                        capabilities: capabilities, promotionNamespace: promotionNamespace,
                        pullNewIcon: pullNewIcon, restoreSavedLocation: restoreSavedLocation, select: select,
                        isExpanded: Binding {
                            if let spacePresentation {
                                return spacePresentation.assignment == configuration.assignment
                                    && spacePresentation.folderIDs.contains(child.id) && !child.isCollapsed
                            }
                            return
                                !(browser.session.space(id: spaceID)?.folders.first { $0.id == child.id }?.isCollapsed
                                ?? true)
                        } set: { expanded in
                            guard configuration.isCurrentAndUnlocked else { return }
                            browser.setFolderCollapsed(
                                child.id, matching: configuration.assignment, isCollapsed: !expanded)
                        },
                        editingFolderRequest: $editingFolderRequest
                    )
                    .padding(.trailing, BrowserFolderLayout.contentsInset)
                    .crestCollectionItemTransition()
                }
            }
        }
        .browserSidebarReorderSectionIndicator(
            .tabs(placement: folder.location.tabPlacement, folderID: folder.id), state: browser.sidebarReorderState)
    }

    private var subtreeTabIDs: [TabID] {
        let ids = tree.descendants(of: folder.id).union([folder.id])
        return tree.folders.filter { ids.contains($0.id) }.flatMap { tabSections.tabs(in: $0.id).map(\.id) }
    }

    private func beginCreatingChild() {
        guard configuration.isCurrentAndUnlocked else { return }
        guard
            let childID = browser.addFolder(
                parentID: folder.id,
                matching: configuration.assignment
            )
        else {
            return
        }
        isExpanded = true
        editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: childID,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID
        )
    }

    private func unloadKeptCollapsedTab(_ tabID: TabID) {
        guard configuration.isCurrentAndUnlocked else { return }
        collapsedTabVisibility.tabDidUnload(tabID)
        configuration.unload(tabID)
    }

    private func beginRenaming() {
        guard configuration.isCurrentAndUnlocked else { return }
        editingFolderRequest = configuration.folderRuntimeAssignment
    }

    private func toggleExpansion() {
        guard !browser.sidebarReorderState.suppressesActivation,
            editingFolderRequest != configuration.folderRuntimeAssignment,
            let liveSpace = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: configuration.assignment, in: browser, accessController: spaceAccess),
            let liveFolder = liveSpace.folders.first(where: { $0.id == folder.id })
        else {
            return
        }
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.disclosure,
                reduceMotion: reduceMotion
            )
        ) {
            let nextExpansion = liveFolder.isCollapsed
            collapsedTabVisibility.expansionDidChange(
                isExpanded: nextExpansion,
                selectedTabID: selectedTabID,
                folderTabIDs: tabs.map(\.id)
            )
            isExpanded = nextExpansion
        }
    }

    private func beginTitleEditingIfNeeded() {
        guard editingFolderRequest == configuration.folderRuntimeAssignment,
            isDeferredAssignmentAvailable(
                configuration.folderRuntimeAssignment
            )
        else {
            isTitleFocused = false
            return
        }
        draftTitle = folder.title
        Task { @MainActor in
            isTitleFocused = true
        }
    }

    private func commitTitle() {
        guard let request = editingFolderRequest else { return }
        editingFolderRequest = nil
        guard isDeferredAssignmentAvailable(request) else { return }
        browser.renameFolder(
            request.folderID,
            matching: request.spaceAssignment,
            title: draftTitle
        )
    }

    private func cancelTitleEditing() {
        guard editingFolderRequest == configuration.folderRuntimeAssignment else {
            return
        }
        draftTitle = folder.title
        editingFolderRequest = nil
    }

    private func deleteFolder() {
        guard let request = deletionRequest else { return }
        deletionRequest = nil
        guard isDeferredAssignmentAvailable(request) else { return }
        browser.deleteFolder(request.folderID, matching: request.spaceAssignment)
    }

    private var folderColorBinding: Binding<BrowserSpaceBrandColor> {
        Binding(
            get: {
                guard let request = colorRequest,
                    isDeferredAssignmentAvailable(request)
                else { return folder.color }
                return browser.space(matching: request.spaceAssignment)?
                    .folders.first(where: { $0.id == request.folderID })?
                    .color ?? folder.color
            },
            set: { color in
                guard let request = colorRequest,
                    isDeferredAssignmentAvailable(request)
                else { return }
                browser.setFolderColor(
                    request.folderID,
                    matching: request.spaceAssignment,
                    color: color
                )
            }
        )
    }

    private var colorPresentation: Binding<Bool> {
        Binding {
            guard let request = colorRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                colorRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                colorRequest = nil
            }
        }
    }

    private var deletionPresentation: Binding<Bool> {
        Binding {
            guard let request = deletionRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                deletionRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                deletionRequest = nil
            }
        }
    }

    private func isDeferredAssignmentAvailable(
        _ request: BrowserFolderRuntimeAssignment
    ) -> Bool {
        guard request == configuration.folderRuntimeAssignment,
            configuration.isCurrentAndUnlocked,
            let space = browser.space(matching: request.spaceAssignment)
        else { return false }
        return space.folders.contains(where: { $0.id == request.folderID })
    }

    private func clearUnavailableDeferredActions() {
        if let request = editingFolderRequest,
            !isDeferredAssignmentAvailable(request)
        {
            editingFolderRequest = nil
            isTitleFocused = false
        }
        if let request = colorRequest,
            !isDeferredAssignmentAvailable(request)
        {
            colorRequest = nil
        }
        if let request = deletionRequest,
            !isDeferredAssignmentAvailable(request)
        {
            deletionRequest = nil
        }
    }
}

/// The full folder keeps its registration for an owned lift, while ordinary
/// input follows the page role entirely within this interaction leaf.
private struct BrowserFolderReorderContainer: ViewModifier {
    let configuration: BrowserFolderGroupConfiguration

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    func body(content: Content) -> some View {
        content.browserSidebarReorderContainer(
            item: .folder(
                BrowserFolderDragItem(
                    folderID: configuration.folder.id,
                    spaceID: configuration.spaceID,
                    profileID: configuration.profileID,
                    memberTabIDs: configuration.subtreeTabIDs)),
            section: configuration.folder.reorderSection,
            reorder: BrowserSidebarReorderContext(
                browser: configuration.browser, spaceAccess: configuration.spaceAccess),
            isEnabled: SidebarSpaceRole.permitsInteraction(
                isSelected: isSelected, isAvailable: configuration.isAvailableForDisplay) || isLiftedFolder
        )
    }

    private var isLiftedFolder: Bool {
        guard let lift = configuration.browser.sidebarReorderState.lift,
            case .folder(let item) = lift.item
        else { return false }
        return item.folderID == configuration.folder.id
            && item.spaceID == configuration.spaceID && item.profileID == configuration.profileID
    }
}

/// The landing slot a folder's tab run keeps open at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell
/// that reserves those places gets a zone of its own here. Where the seam is
/// aimable the reservation would only add an empty band nothing lands in.
private struct BrowserFolderReorderReservation: ViewModifier {
    let configuration: BrowserFolderGroupConfiguration

    @ViewBuilder
    func body(content: Content) -> some View {
        if configuration.capabilities.reservesReorderSectionZones {
            content.browserSidebarReorderSectionReservation(
                .tabs(placement: configuration.folder.location.tabPlacement, folderID: configuration.folder.id),
                state: configuration.browser.sidebarReorderState
            )
        } else {
            content
        }
    }
}
