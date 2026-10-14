import SwiftUI

extension BrowserFolderGroup {
    // MARK: - Variables

    var folderColorBinding: Binding<BrandColor> {
        Binding(
            get: { folder.displayColor },
            set: { color in
                guard let request = colorRequest,
                    isDeferredAssignmentAvailable(request)
                else { return }
                context.browser.setFolderColor(
                    request.folderID,
                    matching: request.spaceAssignment,
                    color: color
                )
            }
        )
    }

    var colorPresentation: Binding<Bool> {
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

    var folderSymbolBinding: Binding<String> {
        Binding(
            get: { folder.displaySymbol },
            set: { symbol in
                guard let request = iconRequest,
                    isDeferredAssignmentAvailable(request)
                else { return }
                context.browser.setFolderSymbol(
                    request.folderID,
                    matching: request.spaceAssignment,
                    symbol: symbol
                )
            }
        )
    }

    var iconPresentation: Binding<Bool> {
        Binding {
            guard let request = iconRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                iconRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                iconRequest = nil
            }
        }
    }

    var deletionPresentation: Binding<Bool> {
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

    // MARK: - Actions - Folders

    /// Nested folders are children of the section they move with, so a parent's
    /// measurement, hover surface and lift include the entire expanded subtree.
    func folderContents(configuration: BrowserFolderGroupConfiguration) -> some View {
        BrowserSidebarListRows(list: configuration.inside, context: context) { items in
            if items.isEmpty { BrowserFolderEmptyRunBand(configuration: configuration) }
        }
        .equatable()
        .browserSidebarReorderSectionIndicator(
            .tabs(placement: folder.location, folderID: folder.id),
            state: sidebarInteraction.sidebarReorderState
        )
        // Each row says its own depth; this is for what the run draws between
        // them, such as the slot a lift leaves.
        .environment(\.sidebarLayerDepth, depth + 1)
    }

    func beginCreatingChild() {
        guard configuration.isCurrentAndUnlocked else { return }
        guard
            let childID = context.browser.addFolder(
                parentID: folder.id,
                matching: configuration.assignment
            )
        else {
            return
        }
        if inheritedKeptTabID != nil { expandFoldersAround() }
        isExpanded.wrappedValue = true
        sidebarInteraction.editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: childID,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID
        )
    }

    /// Opens every collapsed folder that holds this one. A folder drawn on a
    /// collapsed folder's way to its kept tab shows only that way, so a child
    /// made here would stay hidden, and its title could never start editing,
    /// until the folders around it open.
    func expandFoldersAround() {
        var parentID = folder.parentID
        var visited: Set<UUID> = []
        while let id = parentID, visited.insert(id).inserted, let parent = context.space.folders.model(id) {
            if parent.isCollapsed {
                context.browser.setFolderCollapsed(id, matching: configuration.assignment, isCollapsed: false)
            }
            parentID = parent.parentID
        }
    }

    func unloadKeptCollapsedTab(_ tabID: UUID) {
        guard configuration.isCurrentAndUnlocked else { return }
        collapsedTabVisibility.tabDidUnload(tabID)
        context.unload(tabID)
    }

    func beginRenaming() {
        guard configuration.isCurrentAndUnlocked else { return }
        sidebarInteraction.editingFolderRequest = configuration.folderRuntimeAssignment
    }

    func toggleExpansion() {
        guard !sidebarInteraction.sidebarReorderState.suppressesActivation,
            sidebarInteraction.editingFolderRequest != configuration.folderRuntimeAssignment,
            configuration.isCurrentAndUnlocked
        else {
            return
        }
        withAnimation(
            CrestMotion.disclosure.unlessReducingMotion(reduceMotion)
        ) {
            let nextExpansion = folder.isCollapsed
            collapsedTabVisibility.expansionDidChange(
                isExpanded: nextExpansion,
                selectedTabID: configuration.shownFolderTabID,
                folderTabIDs: configuration.folderTabIDs
            )
            isExpanded.wrappedValue = nextExpansion
        }
    }

    func beginTitleEditingIfNeeded() {
        guard sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment,
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

    func commitTitle() {
        guard let request = sidebarInteraction.editingFolderRequest,
            request == configuration.folderRuntimeAssignment
        else { return }
        sidebarInteraction.editingFolderRequest = nil
        guard isDeferredAssignmentAvailable(request) else { return }
        context.browser.renameFolder(
            request.folderID,
            matching: request.spaceAssignment,
            title: draftTitle
        )
    }

    func cancelTitleEditing() {
        guard sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment else {
            return
        }
        draftTitle = folder.title
        sidebarInteraction.editingFolderRequest = nil
    }

    func deleteFolder() {
        guard let request = deletionRequest else { return }
        deletionRequest = nil
        guard isDeferredAssignmentAvailable(request) else { return }
        context.browser.deleteFolder(request.folderID, matching: request.spaceAssignment)
    }

    func isDeferredAssignmentAvailable(
        _ request: BrowserFolderRuntimeAssignment
    ) -> Bool {
        request == configuration.folderRuntimeAssignment && configuration.isCurrentAndUnlocked
    }

    func clearUnavailableDeferredActions() {
        if let request = sidebarInteraction.editingFolderRequest,
            request == configuration.folderRuntimeAssignment,
            !isDeferredAssignmentAvailable(request)
        {
            sidebarInteraction.editingFolderRequest = nil
            isTitleFocused = false
        }
        if let request = iconRequest,
            !isDeferredAssignmentAvailable(request)
        {
            iconRequest = nil
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
