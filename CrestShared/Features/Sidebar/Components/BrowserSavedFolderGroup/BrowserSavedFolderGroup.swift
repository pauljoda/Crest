import SwiftUI

/// One saved folder in the sidebar — its header and the rows it holds — on
/// every shell.
///
/// The group owns the state a folder has to keep between events: whether its
/// title is being edited, which deferred action a menu asked for, and which
/// tab a collapsed folder is still showing. Everything a part needs to draw
/// arrives as `BrowserSavedFolderGroupConfiguration`; everything a part may do
/// arrives as `BrowserSavedFolderGroupInteractionContext`.
///
/// A folder's menu actions outlive the menu that asked for them, so each is
/// held as the folder it was asked for rather than as a bare flag, and every
/// one of them is re-checked against the live session before it runs. A Space
/// can be reselected, relocked, or have the folder deleted out from under an
/// open colour popover, and a request that can no longer be honoured is
/// dropped instead of landing on whatever took its place.
struct BrowserSavedFolderGroup: View {
    let node: BrowserFolderNode
    let tabs: [BrowserTab]
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftTitle = ""
    @State private var colorRequest: BrowserFolderRuntimeAssignment?
    @State private var deletionRequest: BrowserFolderRuntimeAssignment?
    @State private var collapsedTabVisibility =
        BrowserCollapsedFolderTabVisibilityState()
    @FocusState private var isTitleFocused: Bool

    private var folder: SavedFolder { node.folder }

    private var configuration: BrowserSavedFolderGroupConfiguration {
        BrowserSavedFolderGroupConfiguration(
            node: node,
            tabs: tabs,
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
            select: select
        )
    }

    private var interaction: BrowserSavedFolderGroupInteractionContext {
        BrowserSavedFolderGroupInteractionContext(
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
        BrowserSavedFolderGroupSurface(
            configuration: configuration,
            interaction: interaction
        )
        .browserSidebarReorderZone(
            .section(.tabs(placement: .saved, folderID: folder.id)),
            state: browser.sidebarReorderState
        )
        .browserSidebarReorderZone(
            .section(.folders(parentID: folder.id)),
            state: browser.sidebarReorderState,
            topInset: CrestLayout.sidebarRowHeight
        )
        .browserSidebarReorderZone(
            .folder(folder.id),
            state: browser.sidebarReorderState,
            isActive: !isExpanded
        )
        .modifier(
            BrowserSavedFolderReorderReservation(configuration: configuration)
        )
        .onChange(of: configuration.folderRuntimeAssignment) { _, _ in
            clearUnavailableDeferredActions()
        }
        .onChange(of: configuration.isCurrentAndUnlocked) { _, _ in
            clearUnavailableDeferredActions()
        }
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
        guard editingFolderRequest != configuration.folderRuntimeAssignment else {
            return
        }
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.disclosure,
                reduceMotion: reduceMotion
            )
        ) {
            let nextExpansion = !isExpanded
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

/// The landing slot a folder's tab run keeps open at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell
/// that reserves those places gets a zone of its own here. Where the seam is
/// aimable the reservation would only add an empty band nothing lands in.
private struct BrowserSavedFolderReorderReservation: ViewModifier {
    let configuration: BrowserSavedFolderGroupConfiguration

    @ViewBuilder
    func body(content: Content) -> some View {
        if configuration.capabilities.reservesReorderSectionZones {
            content.browserSidebarReorderSectionReservation(
                .tabs(placement: .saved, folderID: configuration.folder.id),
                state: configuration.browser.sidebarReorderState
            )
        } else {
            content
        }
    }
}
