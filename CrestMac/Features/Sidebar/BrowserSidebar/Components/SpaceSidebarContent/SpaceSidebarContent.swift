import SwiftUI

struct SpaceSidebarContent: View {
    let space: BrowserSpace
    let isSelected: Bool
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let openNewTab: () -> Void
    let showHistory: () -> Void
    let showExtensions: () -> Void
    let siteControlPresentationChanged: (Bool) -> Void
    let siteControlContextMenuPresentationChanged: (Bool) -> Void
    let sidebarToggleAction: BrowserSidebarToggleAction
    let toggleSidebar: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    let editSpace: () -> Void
    let createSpace: () -> Void
    let utilitySurface: BrowserUtilitySurface?
    @Binding var utilitySearchText: String
    @Binding var utilityFilter: BrowserUtilityListFilter
    let utilityDownloads: [BrowserDownloadItem]
    let utilityActions: BrowserUtilityListActions
    let dismissUtilityOnBlankSpace: () -> Void
    let clearHistory: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingFolderRequest: BrowserFolderRuntimeAssignment?

    var body: some View {
        VStack(spacing: 0) {
            SidebarNavigationControls(
                browser: browser,
                pages: pages,
                sidebarToggleAction: sidebarToggleAction,
                toggleSidebar: toggleSidebar
            )

            Group {
                if let utilitySurface {
                    if isSelected {
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
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityHidden(true)
                    }
                } else {
                    SpaceSidebarBrowsingContent(
                        space: space,
                        tabSections: space.tabSections,
                        browser: browser,
                        pages: pages,
                        spaceAccess: spaceAccess,
                        isSelected: isSelected,
                        address: $address,
                        isAddressEditing: $isAddressEditing,
                        addressFocusRequest: addressFocusRequest,
                        activateAddress: activateAddress,
                        submitAddress: submitAddress,
                        commandSurfaceNamespace: commandSurfaceNamespace,
                        isSavedTabsExpanded: savedTabsExpansionBinding,
                        openNewTab: openNewTab,
                        beginCreatingFolder: beginCreatingFolder,
                        showHistory: showHistory,
                        showExtensions: showExtensions,
                        siteControlPresentationChanged:
                            siteControlPresentationChanged,
                        siteControlContextMenuPresentationChanged:
                            siteControlContextMenuPresentationChanged,
                        editingFolderRequest: $editingFolderRequest,
                        tabPromotionNamespace: tabPromotionNamespace,
                        editSpace: editSpace,
                        createSpace: createSpace
                    )
                }
            }
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.floatingPane,
                    reduceMotion: reduceMotion
                ),
                value: utilitySurface
            )
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
            browser.space(matching: assignment)?.isSavedTabsExpanded ?? true
        } set: { isExpanded in
            guard isCurrentAndUnlocked else { return }
            browser.setSavedTabsExpanded(isExpanded, matching: assignment)
        }
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
