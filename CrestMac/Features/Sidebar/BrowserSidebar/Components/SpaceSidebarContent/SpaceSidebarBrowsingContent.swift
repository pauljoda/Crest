import SwiftUI

/// One Space's browsing sidebar on the windowed shell: the address band, the
/// pinned grid, the Space header, and the scrolling tab list.
///
/// Everything here is composition and binding. The sections and the list are the
/// shared ones; what this shell adds is its own address band, the pinned
/// extension strip's seam, the scrolling chrome, and the page-facing closures
/// only a windowed card pool can answer.
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

    /// The clear-current-tabs control appears while a pointer rests anywhere
    /// over the list, so the state belongs to the whole scrolling region rather
    /// than to the seam that draws it.
    @State private var isHoveringTabList = false

    var body: some View {
        SpaceSidebarAddressBand(
            space: space,
            pages: pages,
            isSelected: isSelected,
            capabilities: capabilities,
            address: $address,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            activateAddress: activateAddress,
            submitAddress: submitAddress,
            commandSurfaceNamespace: commandSurfaceNamespace,
            showExtensions: showExtensions,
            siteControlPresentationChanged: siteControlPresentationChanged,
            siteControlContextMenuPresentationChanged:
                siteControlContextMenuPresentationChanged,
            hasPinnedExtensionActions: hasPinnedExtensionActions
        )

        BrowserPinnedTabsDropSection(
            space: space,
            tabSections: tabSections,
            browser: browser,
            spaceAccess: spaceAccess,
            pageAccess: pageAccess,
            tabActions: tabActions,
            capabilities: capabilities,
            restoreSavedLocation: restoreSavedLocation,
            select: activate
        )
        .padding(.horizontal, CrestSpacing.small)
        .padding(.top, pinnedTabsTopInset)
        .padding(.bottom, pinnedTabsBottomInset)

        BrowserSpaceHeader(
            space: space,
            isPrivateBrowsing: browser.isPrivateBrowsing,
            isSavedTabsExpanded: $isSavedTabsExpanded,
            capabilities: capabilities,
            actions: BrowserSpaceHeaderActions(
                openNewTab: openNewTab,
                createFolder: beginCreatingFolder,
                showHistory: showHistory,
                showExtensions: showExtensions,
                cleanup: browser.cleanupCurrentTabs
            )
        )

        SpaceSidebarTabListScroll(browser: browser) {
            BrowserSidebarBackgroundInteractionView(
                editSpace: editSpace,
                createSpace: createSpace
            )
        } content: {
            BrowserSidebarTabList(
                space: space,
                tabSections: tabSections,
                browser: browser,
                spaceAccess: spaceAccess,
                pageAccess: pageAccess,
                tabActions: tabActions,
                capabilities: capabilities,
                isSavedTabsExpanded: isSavedTabsExpanded,
                promotionNamespace: tabPromotionNamespace,
                showsClearAction: isHoveringTabList,
                restoreSavedLocation: restoreSavedLocation,
                select: activate,
                openNewTab: openNewTab,
                editingFolderRequest: $editingFolderRequest
            )
        }
        .onHover { isHoveringTabList = $0 }
    }

    /// What this shell can do, until the shell itself hands it down: a pointer
    /// rests over the chrome and nothing is aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: pages, browser: browser)
    }

    private var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    /// Selection and presentation in the one order that works: the page a
    /// shell brings on screen is whichever one the session now points at.
    private func activate(_ tabID: TabID) {
        BrowserTabActivationPolicy.activate(
            tabID,
            selectTab: browser.selectTab,
            presentPage: { pages.select(session: browser.session) }
        )
    }

    private func restoreSavedLocation(_ tabID: TabID) {
        BrowserSavedLocationRestoreAction(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        ).perform(
            BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
    }

    private var hasPinnedExtensionActions: Bool {
        pages.extensionControllerPool.toolbarActions(
            in: space.id,
            tabID: space.selectedTabID
        )
        .contains(where: \.isPinned)
    }

    private var pinnedTabsTopInset: CGFloat {
        guard !tabSections.pinnedTabs.isEmpty else { return 0 }
        return BrowserPinnedExtensionStripLayoutPolicy.pinnedTabsTopInset(
            hasPinnedExtensions: hasPinnedExtensionActions
        )
    }

    private var pinnedTabsBottomInset: CGFloat {
        tabSections.pinnedTabs.isEmpty
            ? 0
            : BrowserSidebarMetrics.pinnedTabsBottomInset
    }
}
