import Foundation
import SwiftUI

extension BrowserCommandPaletteModel {
    // MARK: - Actions - Selection

    func moveSelection(by offset: Int) {
        rejectURLCompletion()
        guard shownSequence == sequence, !items.isEmpty else { return }
        selectedResultIndex = (selectedResultIndex + offset + items.count) % items.count
        keyboardSelectionRevision &+= 1
    }

    /// Moves to the first row of the next or previous section.
    func moveSection(by offset: Int) {
        rejectURLCompletion()
        guard shownSequence == sequence, !groups.isEmpty,
            let current = groups.firstIndex(where: { $0.items.contains { $0.index == selectedResultIndex } }),
            let first = groups[(current + offset + groups.count) % groups.count].items.first
        else { return }
        selectedResultIndex = first.index
        keyboardSelectionRevision &+= 1
    }

    func selectResult(at index: Int) {
        rejectURLCompletion()
        guard shownSequence == sequence, items.indices.contains(index) else { return }
        selectedResultIndex = index
    }

    /// Forgets the row the person moved to: a row whose kind forgets from
    /// history takes its page out of the Space's history, and what the palette
    /// learned about the row goes. The row the palette leads with is never
    /// forgotten this way.
    @discardableResult
    func forgetSelectedRow() -> Bool {
        guard selectedResultIndex > 0, items.indices.contains(selectedResultIndex) else { return false }
        let row = items[selectedResultIndex].row
        guard row.kind.forgetsFromHistory || row.reason == .learned else { return false }
        if row.kind.forgetsFromHistory, let address = row.address, let space {
            browser.removeHistoryAddress(address, in: space.id)
        }
        try? browser.core.send(ForgetPaletteChoices(windowID: browser.windowID, row: row.seed))
        requestAnswer()
        return true
    }

    func activateSelectedResult() {
        guard items.indices.contains(selectedResultIndex) else { return }
        activate(items[selectedResultIndex].row)
    }

    /// Runs `row` as its kind's activation does. One that closes the palette
    /// has it remember the pick for what was typed and close; one that
    /// narrows it, to a provider or a scope, leaves it open.
    func activate(_ row: PaletteRow) {
        guard shownSequence == sequence else { return }
        let activation = row.kind.activation
        let typed = query
        guard BrowserCommandPaletteActivation.of(activation)?.run(row, self) == true, activation.closesPalette else {
            return
        }
        try? browser.core.send(RecordPaletteChoice(windowID: browser.windowID, text: typed, row: row.seed))
        dismiss()
    }

    func dismiss() {
        dismissAction()
    }

    func waitForPendingResults() async {
        await answerTask?.value
    }

    // MARK: - Actions - Activation

    /// Shows the tab `tabID` names in the palette's Space, from the tab the
    /// palette opened over or from the window's New Tab surface.
    func switchToTab(_ tabID: UUID?) -> Bool {
        guard let tabID else { return false }
        if selectedTabID == nil {
            guard let actions = availableEmptySelectionActions, let space else { return false }
            return actions.selectTab(
                BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID))
        }
        guard let sourceAssignment = availableSourceAssignment else { return false }
        return selectTabAction(
            sourceAssignment,
            BrowserTabRuntimeAssignment(
                tabID: tabID, spaceID: sourceAssignment.spaceID, profileID: sourceAssignment.profileID))
    }

    /// Opens `address` where `opening` says, from the tab the palette opened
    /// over, or in the window's New Tab surface, which opens it in place.
    func open(_ address: String?, where opening: BrowserCommandPaletteOpening) -> Bool {
        guard let url = address.flatMap(URL.init(string:)) else { return false }
        if selectedTabID == nil { return availableEmptySelectionActions?.openURL(url) ?? false }
        guard let sourceAssignment = availableSourceAssignment else { return false }
        return openURLAction(sourceAssignment, url, opening)
    }

    /// Where `row` opens while the person holds the keys they hold: where the
    /// keys choose for a row whose activation lets them, else here.
    func opening(for row: PaletteRow) -> BrowserCommandPaletteOpening {
        row.kind.activation.opensWhereKeysChoose
            ? BrowserCommandPaletteOpening.held(heldModifiers, among: openings) : .here
    }

    // MARK: - Actions - Presentation

    /// The tab a row shows, for its icon.
    func tab(for row: PaletteRow) -> TabStateModel? {
        row.tabID.flatMap { space?.tabs.model($0) }
    }

    /// The engine a row's tab runs on, when its icon wears that engine's
    /// badge, for what the row says to VoiceOver.
    func engineBadge(for row: PaletteRow) -> EngineKind? {
        row.tabID.flatMap(browser.core.state.engineBadge(forTab:))
    }

    /// The search provider a row searches with, for its icon.
    func searchProvider(for row: PaletteRow) -> SearchProvider? {
        row.provider
    }
}
