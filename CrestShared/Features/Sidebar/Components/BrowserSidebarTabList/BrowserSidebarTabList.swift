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
/// current run holds anything to clear and whether the saved run keeps a band
/// of its own, each observed apart from the rows, so a move never redraws it.
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
            canClear: holdsCurrentTabs,
            clear: { _ = context.tabActions.clearCurrentTabs() },
            canTidy: canTidy,
            tidy: { try await context.tabActions.tidyCurrentTabs() },
            prepareTidy: OnDeviceTabTidyingService.prewarm
        )
        .background { BrowserTidyBackgroundWork(context: context) }
    }

    /// Whether the person turned Tidy on, the on-device model can run, its word
    /// table is ready, and the current section's top level holds enough web
    /// pages to be worth tidying. Counted without reading titles, so a page
    /// changing its title never redraws the seam.
    private var canTidy: Bool {
        OnDeviceTabTidyingService.isReady
            && OnDeviceTabTidyingService.candidateCount(in: context.space)
                >= OnDeviceTabTidyingService.minimumLooseTabCount
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

/// Keeps Tidy's word table in step with the setting, and has the shown Space's
/// loose tabs described in the background once there are enough of them. It
/// reads every loose tab's title and address, so it sits apart from the seam,
/// and a page changing its title redraws only this.
///
/// While Apple Intelligence is unavailable Tidy only pauses: describing stops,
/// and the table and the keyphrases stay until the person turns Tidy off. A
/// private window's tabs are never described in the background, so nothing
/// about them outlives the window; Tidy reads their titles instead.
private struct BrowserTidyBackgroundWork: View {
    let context: BrowserSidebarListContext

    var body: some View {
        let offersTidy = BrowserAppPreferenceStore.shared.offersTabTidying
        let isTidyEnabled = offersTidy && OnDeviceTabTidyingService.isModelAvailable
        let candidates =
            isTidyEnabled && !context.browser.isPrivateBrowsing && !context.spaceAccess.isLocked(context.space)
            ? OnDeviceTabTidyingService.candidates(in: context.space) : []
        let describedCandidates =
            candidates.count >= OnDeviceTabTidyingService.minimumDescribedTabCount ? candidates : []
        Color.clear
            .task(id: offersTidy) {
                guard !offersTidy else { return }
                TidyTabDescriptions.shared.forgetAll()
                await TidyModelDownloads.shared.sync(isTidyEnabled: false)
            }
            .task(id: isTidyEnabled) {
                guard isTidyEnabled else {
                    TidyTabDescriptions.shared.stopDescribing()
                    return
                }
                await TidyModelDownloads.shared.sync(isTidyEnabled: true)
            }
            .task(id: describedCandidates.map(\.modelDescription)) {
                TidyTabDescriptions.shared.describe(describedCandidates)
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
