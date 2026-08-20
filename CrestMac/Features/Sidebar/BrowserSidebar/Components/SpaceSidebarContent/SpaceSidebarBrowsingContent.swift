import SwiftUI

struct SpaceSidebarBrowsingContent: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let isSelected: Bool
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    @Binding var isSavedTabsExpanded: Bool
    let openNewTab: () -> Void
    let beginCreatingFolder: () -> Void
    let showHistory: () -> Void
    let showExtensions: () -> Void
    let siteControlPresentationChanged: (Bool) -> Void
    let siteControlContextMenuPresentationChanged: (Bool) -> Void
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?
    let tabPromotionNamespace: Namespace.ID
    let editSpace: () -> Void
    let createSpace: () -> Void

    private var selectedTab: BrowserTab? {
        guard let selectedTabID = space.selectedTabID else { return nil }
        return space.tabs.first { $0.id == selectedTabID }
    }

    private var displayedAddress: Binding<String> {
        isSelected
            ? $address
            : .constant(selectedTab?.url?.absoluteString ?? "")
    }

    private var displayedEditing: Binding<Bool> {
        isSelected ? $isAddressEditing : .constant(false)
    }

    private var hasPinnedExtensionActions: Bool {
        pages.extensionControllerPool.toolbarActions(
            in: space.id,
            tabID: space.selectedTabID
        )
        .contains(where: \.isPinned)
    }

    var body: some View {
        BrowserSidebarAddressField(configuration: addressConfiguration) {
            if let siteControl {
                BrowserAddressSecurityButton(
                    page: siteControl.page,
                    isSecure: isSecure
                )
            }
        } trailingAccessory: {
            if let siteControl {
                BrowserSiteControlButton(configuration: siteControl)
            }
        }
        .padding(.horizontal, BrowserChromeLayout.sidebarHorizontalInset)
        .padding(
            .bottom,
            BrowserPinnedExtensionStripLayoutPolicy.addressBottomInset(
                hasPinnedExtensions: hasPinnedExtensionActions
            )
        )

        BrowserPinnedExtensionStrip(
            spaceID: space.id,
            selectedTabID: space.selectedTabID,
            extensionControllerPool: pages.extensionControllerPool
        )

        PinnedTabsDropSection(
            space: space,
            tabSections: tabSections,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
        .padding(.horizontal, CrestSpacing.small)
        .padding(
            .top,
            tabSections.pinnedTabs.isEmpty
                ? 0
                : BrowserPinnedExtensionStripLayoutPolicy.pinnedTabsTopInset(
                    hasPinnedExtensions: hasPinnedExtensionActions
                )
        )
        .padding(
            .bottom,
            tabSections.pinnedTabs.isEmpty
                ? 0
                : BrowserSidebarMetrics.pinnedTabsBottomInset
        )

        SpaceHeader(
            space: space,
            isPrivateBrowsing: browser.isPrivateBrowsing,
            isSavedTabsExpanded: $isSavedTabsExpanded,
            openNewTab: openNewTab,
            createFolder: beginCreatingFolder,
            showHistory: showHistory,
            showExtensions: showExtensions,
            cleanup: browser.cleanupCurrentTabs
        )

        SidebarTabList(
            space: space,
            tabSections: tabSections,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            openNewTab: openNewTab,
            isSavedTabsExpanded: isSavedTabsExpanded,
            editingFolderRequest: $editingFolderRequest,
            tabPromotionNamespace: tabPromotionNamespace,
            editSpace: editSpace,
            createSpace: createSpace
        )
    }

    private var addressConfiguration: BrowserSidebarAddressFieldConfiguration {
        BrowserSidebarAddressFieldConfiguration(
            text: displayedAddress,
            isEditing: displayedEditing,
            focusRequest: addressFocusRequest,
            isSecure: isSecure,
            progress: isSelected ? pages.activePage?.estimatedProgress ?? 0 : 0,
            isLoading: isSelected && pages.activePage?.isLoading == true,
            hasResidentPage: isSelected && pages.activePage != nil,
            hasActiveSite: siteControl != nil,
            capabilities: capabilities,
            activate: activateAddress,
            submit: submitAddress,
            morphNamespace: commandSurfaceNamespace,
            morphID: "crest-address-command-\(space.id)"
        )
    }

    /// What this shell can do, until the shell itself hands it down: a pointer
    /// rests over the chrome and nothing is aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var isSecure: Bool {
        isSelected
            ? pages.activePage?.hasOnlySecureContent == true
            : selectedTab?.url?.scheme?.lowercased() == "https"
    }

    private var siteControl: BrowserSiteControlConfiguration? {
        guard isSelected,
            let page = pages.activePage,
            page.displayURL != nil,
            page.spaceID == space.id
        else {
            return nil
        }
        return BrowserSiteControlConfiguration(
            page: page,
            space: space,
            selectedTabID: space.selectedTabID,
            extensionControllerPool: pages.extensionControllerPool,
            permissionCenter: pages.permissionCenter,
            manageExtensions: showExtensions,
            presentationChanged: siteControlPresentationChanged,
            contextMenuPresentationChanged:
                siteControlContextMenuPresentationChanged
        )
    }
}
