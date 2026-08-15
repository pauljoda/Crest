import SwiftUI
import UniformTypeIdentifiers

struct MobileSavedFolderGroup: View {
    let node: BrowserFolderNode
    let tabs: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectTab: (TabID) -> Void
    let promotionNamespace: Namespace.ID
    let usesNativeNavigationTransition: Bool

    @Binding var isExpanded: Bool
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var draftTitle = ""
    @State private var colorRequest: BrowserFolderRuntimeAssignment?
    @State private var deletionRequest: BrowserFolderRuntimeAssignment?
    @State private var collapsedTabVisibility =
        BrowserCollapsedFolderTabVisibilityState()

    private var folder: SavedFolder { node.folder }
    private var dropLocation: BrowserTabDropLocation {
        .init(placement: .saved, folderID: folder.id, beforeTabID: nil)
    }
    private var folderDropLocation: BrowserFolderDropLocation {
        .init(parentID: folder.parentID, beforeSiblingID: folder.id)
    }

    var body: some View {
        let followingTabIDs = BrowserTabRowInsertionPolicy.followingTabIDs(in: tabs)
        let items = BrowserSidebarTabListItemPolicy.items(for: tabs)

        VStack(spacing: 0) {
            MobileSavedFolderHeader(
                folder: folder,
                depth: node.depth,
                isExpanded: isExpanded,
                isEditing: editingFolderRequest == folderRuntimeAssignment
                    && isDeferredAssignmentAvailable(folderRuntimeAssignment),
                draftTitle: $draftTitle,
                toggleExpansion: toggleExpansion,
                commitTitle: commitTitle
            )
            .accessibilityLabel("\(folder.title) folder")
            .accessibilityValue(
                BrowserChromeAccessibility.folderValue(isExpanded: isExpanded)
            )
            .accessibilityHint(
                isExpanded ? "Collapses this folder" : "Expands this folder"
            )
            .crestInteractiveSurface(
                isSelected: BrowserFolderRowPresentationPolicy.showsDropHighlight(
                    isTargeted: isDropTargeted,
                    isTabDragging: browser.tabDragState.item != nil
                ),
                isHovering: false,
                cornerRadius: CrestLayout.sidebarControlCornerRadius
            )
            .padding(.horizontal, CrestSpacing.small)
            .browserFolderDraggable(
                folder: folder,
                profileID: profileID,
                spaceID: spaceID,
                dragState: browser.folderDragState,
                reorder: BrowserSidebarReorderContext(
                    browser: browser,
                    spaceAccess: spaceAccess
                ),
                isEnabled: editingFolderRequest != folderRuntimeAssignment
                    && isCurrentAndUnlocked
            )
            .overlay(alignment: .bottom) {
                BrowserFolderDropIndicator(
                    location: folderDropLocation,
                    dragState: browser.folderDragState,
                    isTargeted: isDropTargeted
                )
            }

            if isExpanded {
                ForEach(items) { item in
                    switch item {
                    case .tab(let tab):
                        let followingTabID = followingTabIDs[tab.id]
                        MobileSidebarTabRow(
                            tab: tab,
                            followingTabID: followingTabID,
                            hasVisibleFollowingRow: followingTabID != nil,
                            spaceID: spaceID,
                            profileID: profileID,
                            isSelected: tab.id == selectedTabID,
                            canClose: false,
                            browser: browser,
                            spaceAccess: spaceAccess,
                            isLoaded: pages.containsResidentPage(for: tab.id),
                            unload: { tabID in
                                pages.unloadPage(for: tabID, matching: assignment)
                            },
                            pullNewIcon: { pullNewIcon(tab.id) },
                            restoreSavedLocation: { restoreSavedLocation(tab.id) },
                            promotionNamespace: promotionNamespace,
                            usesNativeNavigationTransition: usesNativeNavigationTransition,
                            select: selectTab
                        )
                        .padding(.leading, nestingInset)
                        .id(tab.id)
                    case .splitGroup(let groupID, let members):
                        let followingTabID = members.last.flatMap {
                            followingTabIDs[$0.id]
                        }
                        MobileSidebarSplitGroupRow(
                            groupID: groupID,
                            members: members,
                            followingTabID: followingTabID,
                            hasVisibleFollowingRow: followingTabID != nil,
                            spaceID: spaceID,
                            profileID: profileID,
                            selectedTabID: selectedTabID,
                            canClose: false,
                            browser: browser,
                            spaceAccess: spaceAccess,
                            isLoaded: { pages.containsResidentPage(for: $0) },
                            promotionNamespace: promotionNamespace,
                            usesNativeNavigationTransition: usesNativeNavigationTransition,
                            select: selectTab
                        )
                        .padding(.leading, nestingInset)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let keptTab = keptCollapsedTab {
                MobileSidebarTabRow(
                    tab: keptTab,
                    followingTabID: followingTabIDs[keptTab.id],
                    hasVisibleFollowingRow: false,
                    spaceID: spaceID,
                    profileID: profileID,
                    isSelected: keptTab.id == selectedTabID,
                    canClose: false,
                    browser: browser,
                    spaceAccess: spaceAccess,
                    isLoaded: true,
                    unload: unloadKeptCollapsedTab,
                    pullNewIcon: { pullNewIcon(keptTab.id) },
                    restoreSavedLocation: { restoreSavedLocation(keptTab.id) },
                    promotionNamespace: promotionNamespace,
                    usesNativeNavigationTransition: usesNativeNavigationTransition,
                    select: selectTab
                )
                .padding(.leading, nestingInset)
                .transition(.opacity)
            }
        }
        .contextMenu {
            BrowserFolderOrganizationMenu(
                folder: folder,
                assignment: BrowserFolderRuntimeAssignment(
                    folderID: folder.id,
                    spaceID: spaceID,
                    profileID: profileID
                ),
                browser: browser,
                spaceAccess: spaceAccess,
                createNestedFolder: beginCreatingChild,
                renameFolder: beginRenaming,
                changeColor: { colorPresentation.wrappedValue = true },
                deleteFolder: { deletionPresentation.wrappedValue = true }
            )
            .tint(.primary)
            .onAppear {
                browser.folderDragState.contextMenuDidOpen(
                    for: BrowserFolderDragItem(
                        folderID: folder.id,
                        spaceID: spaceID,
                        profileID: profileID
                    )
                )
            }
            .onDisappear {
                browser.folderDragState.contextMenuDidClose(
                    for: BrowserFolderDragItem(
                        folderID: folder.id,
                        spaceID: spaceID,
                        profileID: profileID
                    )
                )
            }
        }
        .popover(isPresented: colorPresentation) {
            BrowserFolderColorPicker(color: folderColorBinding)
                .presentationCompactAdaptation(.sheet)
        }
        .confirmationDialog(
            "Delete \(folder.title)?",
            isPresented: deletionPresentation,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                guard let request = deletionRequest else { return }
                deletionRequest = nil
                guard isDeferredAssignmentAvailable(request) else { return }
                browser.deleteFolder(
                    request.folderID,
                    matching: request.spaceAssignment
                )
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
            value: tabs.map(\.id)
        )
        .onChange(of: isExpanded, initial: true) { _, isExpanded in
            collapsedTabVisibility.expansionDidChange(
                isExpanded: isExpanded,
                selectedTabID: selectedTabID,
                folderTabIDs: tabs.map(\.id)
            )
        }
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
        .onChange(of: folderRuntimeAssignment) { _, _ in
            clearUnavailableDeferredActions()
        }
        .onChange(of: isCurrentAndUnlocked) { _, _ in
            clearUnavailableDeferredActions()
        }
    }

    private func beginCreatingChild() {
        guard isCurrentAndUnlocked else { return }
        guard
            let childID = browser.addFolder(
                parentID: folder.id,
                matching: assignment
            )
        else { return }
        isExpanded = true
        editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: childID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    /// Rows inside a folder step in one indent per level, plus one for the folder
    /// itself, so a group row lines up with the tab rows beside it.
    private var nestingInset: CGFloat {
        MobileSidebarRowLayoutPolicy.folderNestingIndent
            * CGFloat(node.depth + 1)
    }

    private var keptCollapsedTab: BrowserTab? {
        guard let keptTabID = collapsedTabVisibility.keptTabID,
            pages.containsResidentPage(for: keptTabID)
        else {
            return nil
        }
        return tabs.first { $0.id == keptTabID }
    }

    private func unloadKeptCollapsedTab(_ tabID: TabID) {
        guard isCurrentAndUnlocked else { return }
        collapsedTabVisibility.tabDidUnload(tabID)
        pages.unloadPage(for: tabID, matching: assignment)
    }

    private func beginRenaming() {
        guard isCurrentAndUnlocked else { return }
        editingFolderRequest = folderRuntimeAssignment
    }

    private func toggleExpansion() {
        guard editingFolderRequest != folderRuntimeAssignment else { return }
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

    private func pullNewIcon(_ tabID: TabID) {
        let actions = MobileBrowserSidebarTabActions(
            assignment: assignment,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
        Task {
            await actions.pullNewIcon(for: tabID)
        }
    }

    private func restoreSavedLocation(_ tabID: TabID) {
        guard isCurrentAndUnlocked else { return }
        MobileSavedLocationRestoreAction(
            browser: browser,
            pages: pages,
            selectTab: selectTab
        ).perform(
            BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: spaceID,
                profileID: profileID
            )
        )
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    private var folderRuntimeAssignment: BrowserFolderRuntimeAssignment {
        BrowserFolderRuntimeAssignment(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    private var colorPresentation: Binding<Bool> {
        Binding {
            guard let request = colorRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, isCurrentAndUnlocked {
                colorRequest = folderRuntimeAssignment
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
            if isPresented, isCurrentAndUnlocked {
                deletionRequest = folderRuntimeAssignment
            } else if !isPresented {
                deletionRequest = nil
            }
        }
    }

    private func isDeferredAssignmentAvailable(
        _ request: BrowserFolderRuntimeAssignment
    ) -> Bool {
        guard request == folderRuntimeAssignment,
            isCurrentAndUnlocked,
            let space = browser.space(matching: request.spaceAssignment)
        else { return false }
        return space.folders.contains(where: { $0.id == request.folderID })
    }

    private func clearUnavailableDeferredActions() {
        if let request = editingFolderRequest,
            !isDeferredAssignmentAvailable(request)
        {
            editingFolderRequest = nil
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

    private var isCurrentAndUnlocked: Bool {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }
}

#Preview("Mobile Saved Folder Group") {
    @Previewable @Namespace var promotionNamespace
    @Previewable @State var isExpanded = true
    @Previewable @State var editingFolderRequest: BrowserFolderRuntimeAssignment? = nil
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileSavedFolderGroup(
        node: fixture.folderNode,
        tabs: [fixture.savedTab],
        spaceID: fixture.space.id,
        profileID: fixture.space.profile.id,
        selectedTabID: fixture.space.selectedTabID,
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        selectTab: { _ in },
        promotionNamespace: promotionNamespace,
        usesNativeNavigationTransition: false,
        isExpanded: $isExpanded,
        editingFolderRequest: $editingFolderRequest
    )
    .frame(width: 360)
}
