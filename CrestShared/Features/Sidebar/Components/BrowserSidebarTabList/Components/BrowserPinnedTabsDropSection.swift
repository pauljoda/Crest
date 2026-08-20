import SwiftUI

/// The Space's pinned tabs as one drop section, on every shell.
///
/// What differs between a pointer shell and a touch one is read from
/// `BrowserSidebarInteractionPolicy` rather than from which target compiled the
/// file. What the two shells genuinely cannot share — where a page lives, what
/// opening a tab means to the host, how a tab gets home — arrives as the page
/// seam and a handful of closures the host binds.
struct BrowserPinnedTabsDropSection: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let pageAccess: BrowserSidebarPageAccess
    let tabActions: BrowserSidebarTabActions
    let capabilities: BrowserInteractionCapabilities
    var promotionNamespace: Namespace.ID? = nil
    /// How a pinned tab gets back to the page it was saved from. The two shells
    /// answer that differently, so the host binds it.
    let restoreSavedLocation: (TabID) -> Void
    /// What opening a pinned tab means to the host. The section decides
    /// *whether*; the host decides what appears.
    let select: (TabID) -> Void

    var body: some View {
        Group {
            if tabSections.pinnedTabs.isEmpty {
                // A grid nobody has filled still takes a drop, and without a
                // band of its own it has no region to aim at and nowhere to
                // draw its insertion line.
                Color.clear
                    .frame(height: metrics.sectionEndBandHeight)
                    .contentShape(.rect)
                    .accessibilityHidden(true)
            } else {
                PinnedTabGrid(
                    tabs: tabSections.pinnedTabs,
                    assignment: assignment,
                    selectedTabID: space.selectedTabID,
                    select: { runtimeAssignment in
                        guard isCurrentAndUnlocked else { return }
                        select(runtimeAssignment.tabID)
                    },
                    moveTab: move,
                    dragState: browser.tabDragState,
                    browser: browser,
                    spaceAccess: spaceAccess,
                    isLoaded: pageAccess.containsResidentPageMatching,
                    unload: { runtimeAssignment in
                        pageAccess.unloadPage(runtimeAssignment.tabID, assignment)
                    },
                    pullNewIcon: { pullNewIcon($0.tabID) },
                    restoreSavedLocation: { restoreSavedLocation($0.tabID) },
                    siteThemeAccent: pageAccess.siteThemeIconAccent,
                    promotionNamespace: promotionNamespace,
                    capabilities: capabilities
                )
            }
        }
        .contentShape(.rect)
        .browserSidebarReorderSectionIndicator(
            .tabs(placement: .pinned, folderID: nil),
            state: browser.sidebarReorderState
        )
        // On the whole section, not just the empty placeholder: a zone inside
        // one branch vanishes the moment any tab is pinned, and dragging into a
        // populated grid becomes impossible.
        .browserSidebarReorderZone(
            .section(.tabs(placement: .pinned, folderID: nil)),
            state: browser.sidebarReorderState
        )
        .accessibilityHint("Drop a tab here to pin it")
    }

    private var metrics: BrowserSidebarTabListMetrics {
        BrowserSidebarInteractionPolicy.tabListMetrics(capabilities)
    }

    private func move(
        _ item: BrowserTabDragItem,
        before tabID: TabID?
    ) -> Bool {
        guard isCurrentAndUnlocked else { return false }
        return BrowserTabDragAction(
            browser: browser,
            spaceAccess: spaceAccess
        ).move(
            item,
            to: .pinned,
            before: tabID,
            matching: assignment
        )
    }

    private func pullNewIcon(_ tabID: TabID) {
        let actions = tabActions
        Task {
            await actions.pullNewIcon(for: tabID)
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
