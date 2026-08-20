import SwiftUI

/// The sidebar's tab list, on every shell: the saved run, the seam below it, and
/// the current run.
///
/// The list owns the order those three appear in and nothing else. Each shell
/// wraps it in its own scrolling chrome — the windowed shell fills the space
/// below with a draggable background, the compact one keeps the list eager so a
/// promoted row has a resting frame — and drops this composition inside it.
struct BrowserSidebarTabList: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let pageAccess: BrowserSidebarPageAccess
    let tabActions: BrowserSidebarTabActions
    let capabilities: BrowserInteractionCapabilities
    let isSavedTabsExpanded: Bool
    /// The namespace a current-tabs row anchors the page it opens in.
    var promotionNamespace: Namespace.ID? = nil
    /// The namespace a saved row anchors the page it opens in. The windowed
    /// shell anchors only its current run, so it passes nothing here.
    var savedPromotionNamespace: Namespace.ID? = nil
    /// Whether the shell is in the state that reveals the seam's clear control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    /// How a saved tab gets back to the page it was saved from.
    let restoreSavedLocation: (TabID) -> Void
    /// What opening a tab means to the host.
    let select: (TabID) -> Void
    let openNewTab: () -> Void
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?

    var body: some View {
        if isSavedTabsExpanded {
            BrowserSavedTabsDropSection(
                space: space,
                tabSections: tabSections,
                browser: browser,
                spaceAccess: spaceAccess,
                pageAccess: pageAccess,
                tabActions: tabActions,
                capabilities: capabilities,
                promotionNamespace: savedPromotionNamespace,
                restoreSavedLocation: restoreSavedLocation,
                select: select,
                editingFolderRequest: $editingFolderRequest
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        BrowserCurrentTabsDivider(
            capabilities: capabilities,
            showsClearAction: showsClearAction,
            canClear: !tabSections.sidebarCurrentTabs.isEmpty,
            clear: clearCurrentTabs
        )

        BrowserCurrentTabsDropSection(
            space: space,
            tabSections: tabSections,
            browser: browser,
            spaceAccess: spaceAccess,
            pageAccess: pageAccess,
            tabActions: tabActions,
            capabilities: capabilities,
            promotionNamespace: promotionNamespace,
            select: select,
            openNewTab: openNewTab
        )
    }

    private func clearCurrentTabs() {
        _ = tabActions.clearCurrentTabs()
    }
}
