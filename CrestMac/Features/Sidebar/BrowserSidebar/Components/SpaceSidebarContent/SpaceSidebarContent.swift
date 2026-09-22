import SwiftUI

struct SpaceSidebarContent: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let space: BrowserSpace
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    let openNewTab: () -> Void
    let showHistory: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    let editSpace: () -> Void
    let createSpace: (() -> Void)?
    let utilitySurface: BrowserUtilitySurface?
    @Binding var utilitySearchText: String
    @Binding var utilityFilter: BrowserUtilityListFilter
    let utilityDownloads: [BrowserDownloadItem]
    let utilityActions: BrowserUtilityListActions
    let dismissUtilityOnBlankSpace: () -> Void
    let clearHistory: () -> Void

    @State private var editingFolderRequest: BrowserFolderRuntimeAssignment?

    var body: some View {
        VStack(spacing: 0) {
            if utilitySurface == nil {
                BrowserEngineSidebarAccessory(space: space, pages: pages)
            }
            Group {
                if let utilitySurface {
                    SpaceSidebarUtilityContent(
                        surface: utilitySurface,
                        space: space,
                        searchText: $utilitySearchText,
                        filter: $utilityFilter,
                        commandSurfaceNamespace: commandSurfaceNamespace,
                        downloads: utilityDownloads,
                        actions: utilityActions,
                        dismissOnBlankSpace: dismissUtilityOnBlankSpace,
                        clearHistory: clearHistory
                    )
                } else {
                    SpaceSidebarBrowsingContent(
                        space: space,
                        tabSections: space.tabSections,
                        browser: browser,
                        pages: pages,
                        spaceAccess: spaceAccess,
                        capabilities: capabilities,
                        isSavedTabsExpanded: savedTabsExpansionBinding,
                        toggleSavedTabs: toggleSavedTabs,
                        openNewTab: openNewTab,
                        beginCreatingFolder: beginCreatingFolder,
                        showHistory: showHistory,
                        editingFolderRequest: $editingFolderRequest,
                        tabPromotionNamespace: tabPromotionNamespace,
                        editSpace: editSpace,
                        createSpace: createSpace
                    )
                }
            }
        }
        .onChange(of: utilitySurface != nil) { _, isPresented in
            // The utility surface replaces every browsing input host.
            if isPresented { sidebarInteraction.cancel() }
        }
    }

    private func beginCreatingFolder() {
        guard isCurrentAndUnlocked,
            let folderID = browser.addFolder(matching: assignment)
        else { return }
        browser.setSavedTabsExpanded(true, matching: assignment)
        editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: folderID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    private var savedTabsExpansionBinding: Binding<Bool> {
        Binding {
            space.isSavedTabsExpanded
        } set: { isExpanded in
            guard isCurrentAndUnlocked else { return }
            browser.setSavedTabsExpanded(isExpanded, matching: assignment)
        }
    }

    private func toggleSavedTabs() {
        guard
            let liveSpace = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment, in: browser, accessController: spaceAccess)
        else { return }
        browser.setSavedTabsExpanded(!liveSpace.isSavedTabsExpanded, matching: assignment)
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    private var isCurrentAndUnlocked: Bool {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }
}
