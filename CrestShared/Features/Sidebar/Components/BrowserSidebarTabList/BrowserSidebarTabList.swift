import SwiftUI

/// The sidebar's tab list, on every shell: the saved run, the seam below it, and
/// the current run.
///
/// The list owns the order those three appear in and nothing else. It reads
/// only whether the saved section is open; each section reads its own list, so
/// a move, a collapse or another shown tab never redraws it. Each shell wraps
/// it in its own scrolling chrome and drops this composition inside it.
struct BrowserSidebarTabList: View {
    let context: BrowserSidebarListContext
    /// Shows the saved section whatever the Space says, for a surface that
    /// always shows it.
    var alwaysShowsSavedTabs = false
    /// Whether the shell is in the state that reveals the seam's clear control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    let openNewTab: () -> Void

    var body: some View {
        let isSavedTabsExpanded = alwaysShowsSavedTabs || context.space.settings.isSavedTabsExpanded
        if isSavedTabsExpanded {
            BrowserSavedTabsDropSection(context: context)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        BrowserCurrentTabsSeam(
            context: context, isSavedTabsExpanded: isSavedTabsExpanded, showsClearAction: showsClearAction)

        BrowserCurrentTabsDropSection(context: context, openNewTab: openNewTab)
    }
}

/// The seam between the saved run and the current one. It reads whether the
/// current run holds anything to clear, with and without the shown tab, and
/// whether the saved run keeps a band of its own, each observed apart from the
/// rows.
private struct BrowserCurrentTabsSeam: View {
    let context: BrowserSidebarListContext
    let isSavedTabsExpanded: Bool
    let showsClearAction: Bool

    var body: some View {
        let sidebar = context.space.sidebar
        BrowserCurrentTabsDivider(
            capabilities: context.capabilities,
            hasSavedTabsEndBand: isSavedTabsExpanded
                && (context.capabilities.reservesReorderSectionZones || !sidebar.section(.saved).holdsTabRows),
            showsClearAction: showsClearAction,
            canClearOthers: holdsCurrentTabs && holdsTabsBesideShownTab,
            canClearAll: holdsCurrentTabs,
            clearOthers: { _ = context.tabActions.clearCurrentTabs(keepingShownTab: true) },
            clearAll: { _ = context.tabActions.clearCurrentTabs(keepingShownTab: false) },
            canTidy: context.tabActions.canTidy,
            isTidying: TabTidying.shared.tidyingSpaceIDs.contains(context.space.id),
            tidyFailed: TabTidying.shared.failedSpaceIDs.contains(context.space.id),
            tidy: { context.tabActions.startTidying() },
            prepareTidy: { TabTidying.shared.prewarm() }
        )
        .background { BrowserTidyBackgroundWork(context: context) }
    }

    /// Whether the current run holds a tab other than the one the window
    /// shows and the rest of its split, which Clear keeps.
    private var holdsTabsBesideShownTab: Bool {
        !context.browser.clearedTabIDs(of: context.space, keepingShownTab: true).isEmpty
    }

    /// Whether the current section holds a tab, at its top level or in one of
    /// its folders. Its rows are read only when the top level holds folders
    /// and no tab.
    private var holdsCurrentTabs: Bool {
        let space = context.space
        let current = space.sidebar.section(.current)
        guard !current.holdsTabRows else { return true }
        guard !current.isEmpty else { return false }
        return current.rows.contains { $0.kind.opensList && !space.tabIDs(inFolder: $0.id).isEmpty }
    }
}

/// Has the shown Space's loose tabs described in the background while Tidy
/// is on, once there are enough of them. It reads every loose tab's title and
/// address, so it sits apart from the seam, and a page changing its title
/// redraws only this. A locked Space's tabs, and a private window's, are
/// never described.
private struct BrowserTidyBackgroundWork: View {
    let context: BrowserSidebarListContext

    var body: some View {
        let tidying = TabTidying.shared
        let candidates =
            tidying.isOn && TabTidying.isModelAvailable && !context.spaceAccess.isLocked(context.space)
            ? TabTidying.candidates(in: context.space, of: context.browser) : []
        Color.clear
            .task(id: candidates.map(\.modelDescription)) {
                tidying.describe(candidates)
            }
    }
}

extension BrowserSidebarTabList: @MainActor Equatable {
    /// The list is equal to one over the same Space and window with the same
    /// settings, as SwiftUI compares a view's inputs: a page that redraws for
    /// anything else leaves the list alone.
    static func == (lhs: BrowserSidebarTabList, rhs: BrowserSidebarTabList) -> Bool {
        lhs.context == rhs.context && lhs.alwaysShowsSavedTabs == rhs.alwaysShowsSavedTabs
            && lhs.showsClearAction == rhs.showsClearAction
    }
}
