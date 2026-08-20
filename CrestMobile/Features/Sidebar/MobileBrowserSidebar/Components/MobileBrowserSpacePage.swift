import SwiftUI

/// One Space's sidebar on the compact shell: the pinned grid, the Space header,
/// and the scrolling tab list.
///
/// Everything here is composition and binding. The sections and the list are the
/// shared ones; what this shell adds is its own scrolling chrome, the drop feed
/// that covers the whole sidebar, and the page-facing closures only a single
/// compact page can answer.
struct MobileBrowserSpacePage: View {
    let space: BrowserSpace
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    let tabPromotionNamespace: Namespace.ID
    let selectTab: (TabID) -> Void
    let openNewTab: () -> Void
    let showHistory: () -> Void
    let showPasswords: () -> Void
    let showSettings: () -> Void
    let closePrivateBrowsing: () -> Void
    let compactPageIsFullyPresented: Bool

    @Environment(\.openWindow) private var openWindow
    @State private var editingFolderRequest: BrowserFolderRuntimeAssignment?

    var body: some View {
        let tabSections = space.tabSections

        VStack(spacing: 0) {
            BrowserPinnedTabsDropSection(
                space: space,
                tabSections: tabSections,
                browser: browser,
                spaceAccess: spaceAccess,
                pageAccess: pageAccess,
                tabActions: tabActions,
                capabilities: capabilities,
                promotionNamespace: tabPromotionNamespace,
                restoreSavedLocation: restoreSavedLocation,
                select: selectTab
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            BrowserSpaceHeader(
                space: space,
                isPrivateBrowsing: browser.isPrivateBrowsing,
                isSavedTabsExpanded: savedTabsExpansionBinding,
                capabilities: capabilities,
                actions: BrowserSpaceHeaderActions(
                    openNewTab: openNewTab,
                    openNewWindow: { openWindow(value: BrowserWindowID()) },
                    createFolder: beginCreatingFolder,
                    showHistory: showHistory,
                    showPasswords: showPasswords,
                    closePrivateBrowsing: closePrivateBrowsing,
                    showSettings: showSettings,
                    cleanup: browser.cleanupCurrentTabs
                )
            )

            MobileBrowserSpaceTabListScroll(
                space: space,
                browser: browser,
                compactPageIsFullyPresented: compactPageIsFullyPresented
            ) {
                BrowserSidebarTabList(
                    space: space,
                    tabSections: tabSections,
                    browser: browser,
                    spaceAccess: spaceAccess,
                    pageAccess: pageAccess,
                    tabActions: tabActions,
                    capabilities: capabilities,
                    isSavedTabsExpanded: space.isSavedTabsExpanded,
                    promotionNamespace: tabPromotionNamespace,
                    savedPromotionNamespace: tabPromotionNamespace,
                    restoreSavedLocation: restoreSavedLocation,
                    select: selectTab,
                    openNewTab: openNewTabIfAvailable,
                    editingFolderRequest: $editingFolderRequest
                )
            }
        }
        .modifier(
            MobileBrowserSidebarReorderDropFeed(
                browser: browser,
                spaceAccess: spaceAccess
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            BrowserSpaceAccessibilityID.sidebar(space.id)
        )
        .accessibilityLabel("\(space.name) Space sidebar")
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: pages, browser: browser)
    }

    private var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: assignment,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    private func openNewTabIfAvailable() {
        guard isCurrentAndUnlocked else { return }
        openNewTab()
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
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
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
