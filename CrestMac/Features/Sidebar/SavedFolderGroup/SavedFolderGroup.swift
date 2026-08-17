import SwiftUI

struct SavedFolderGroup: View {
    let node: BrowserFolderNode
    let tabs: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController

    @Binding var isExpanded: Bool
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var draftTitle = ""
    @State private var colorRequest: BrowserFolderRuntimeAssignment?
    @State private var deletionRequest: BrowserFolderRuntimeAssignment?
    @State private var collapsedTabVisibility =
        BrowserCollapsedFolderTabVisibilityState()
    @FocusState private var isTitleFocused: Bool

    private var folder: SavedFolder { node.folder }

    private var configuration: SavedFolderGroupConfiguration {
        SavedFolderGroupConfiguration(
            node: node,
            tabs: tabs,
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: selectedTabID,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    private var interaction: SavedFolderGroupInteractionContext {
        SavedFolderGroupInteractionContext(
            isExpanded: $isExpanded,
            editingFolderRequest: $editingFolderRequest,
            isDropTargeted: $isDropTargeted,
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
        SavedFolderGroupSurface(
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
        pages.unloadPage(for: tabID, matching: configuration.assignment)
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
