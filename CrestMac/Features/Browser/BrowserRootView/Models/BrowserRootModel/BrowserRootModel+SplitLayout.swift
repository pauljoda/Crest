import SwiftUI

extension BrowserRootModel {
    /// The cards the content area presents for the current selection.
    ///
    /// Derived from the session rather than read out of
    /// `BrowserPagePool.presentedTabIDs`: both answer the same
    /// `presentedSplitMembers(for:)` question, and taking the store's answer is
    /// what keeps SwiftUI observing the thing that actually changes when
    /// membership does.
    var presentedSplitMembers: [BrowserTab] {
        guard let space = browser.selectedSpace else { return [] }
        return space.presentedSplitMembers(for: browser.selectedTab?.id)
    }

    /// The group the presented cards belong to, or `nil` when one tab presents
    /// alone. Column fractions are stored per group, so a lone tab has no
    /// layout to store.
    var presentedSplitGroupID: SplitGroupID? {
        guard let space = browser.selectedSpace,
            let selectedTabID = browser.selectedTab?.id
        else { return nil }
        return space.splitGroup(containing: selectedTabID)
    }

    var splitWidthTransactionBinding: Binding<BrowserSplitWidthTransaction> {
        Binding(
            get: { self.splitWidthTransaction },
            set: { self.splitWidthTransaction = $0 }
        )
    }

    /// Adopts the layout this window last stored for the presented group.
    ///
    /// Called whenever the presented membership changes — a different group, a
    /// member joining or leaving, members reordering — because fractions are
    /// positional and a list written for one arrangement means nothing under
    /// another. A group this window has never resized starts as equal columns.
    func seedSplitColumnFractions() {
        let members = presentedSplitMembers
        guard !members.isEmpty else { return }
        let persisted = presentedSplitGroupID.flatMap { groupID in
            windowState?.splitColumnFractions(for: groupID)
        }
        splitWidthTransaction.begin(
            fractions: BrowserSplitLayoutSeedPolicy.fractions(
                persisted: persisted,
                memberCount: members.count
            )
        )
    }

    /// Records what a completed divider drag settled on. Column widths are a
    /// per-window, device-local preference and never reach the session or sync.
    func commitSplitColumnFractions(_ fractions: [Double]) {
        guard let windowState, let groupID = presentedSplitGroupID else { return }
        windowState.captureSplitLayout(fractions: fractions, for: groupID)
    }

    /// Makes one presented card the focused card.
    ///
    /// Focus *is* selection, so this is an ordinary selection change: the
    /// existing selection observer re-presents the group with the new focus and
    /// every chrome surface follows without a second focus state anywhere.
    func focusSplitCard(_ tabID: TabID) {
        guard tabID != browser.selectedTab?.id,
            presentedSplitMembers.contains(where: { $0.id == tabID })
        else { return }
        browser.selectTab(tabID)
    }
}
