import Foundation
import SwiftUI

extension BrowserCommandPaletteModel {
    // MARK: - Actions - Completion

    func updateCompletionEditing(text: String, selection: NSRange, isComposing: Bool) {
        let couldPropose = completionEditing.canPropose(for: query)
        completionEditing.update(text: text, selection: selection, isComposing: isComposing)
        if !isComposing { query = text }
        // The core leads with the completion only while the field may show
        // it, so a caret that moves away asks again.
        if !isComposing, text == query, couldPropose != completionEditing.canPropose(for: query) { requestAnswer() }
    }

    func rejectURLCompletion() { completionEditing.reject() }

    func invalidateURLCompletion() {
        completionProposal = nil
        completionEditing.reject()
    }

    @discardableResult
    func acceptURLCompletion() -> Bool {
        guard let proposal = urlCompletion, let applyCompletion else { return false }
        completionEditing.reject()
        applyCompletion(proposal.insertionText, proposal.insertionRange)
        // Return right after Tab must find the accepted address as the primary
        // action even before the off-main answer arrives.
        if query == proposal.accepted, let answer = try? browser.core.query(question(for: query)) {
            show(answer, for: sequence)
            selectedResultIndex = 0
        }
        completionEditing.reject()
        return true
    }

    // MARK: - Actions - Keys

    /// Tab cycles rows when provider entry is off. Otherwise it enters the
    /// search provider whose shortcut the text is, else
    /// accepts the completion the field shows, else enters the provider or
    /// scope the text names, else moves to the next row. It never moves focus
    /// out of the field.
    func pressTab() {
        waitForAnswer { [weak self] in
            guard let self else { return }
            guard preferences.searchesSitesWithTab else {
                moveSelection(by: 1)
                return
            }
            if let provider = providerOffer {
                enter(provider)
                return
            }
            if acceptURLCompletion() { return }
            if let scope = scopeOffer {
                enter(scope)
            } else {
                moveSelection(by: 1)
            }
        }
    }

    /// Shift-Tab moves to the row before.
    func pressBacktab() { moveSelection(by: -1) }

    /// Return runs the selected row, once the answer to what was typed arrived.
    func pressReturn() {
        waitForAnswer { [weak self] in self?.activateSelectedResult() }
    }

    /// Down moves to the next row, once the answer to what was typed arrived.
    func pressDown() {
        waitForAnswer { [weak self] in self?.moveSelection(by: 1) }
    }

    /// Notes the modifier keys the person holds.
    func updateHeldModifiers(_ modifiers: EventModifiers) {
        let held = modifiers.intersection([.command, .shift, .option])
        if held != heldModifiers { heldModifiers = held }
    }

    /// Runs `key` now when the rows answer what was typed, or once they do,
    /// or after a short wait on the rows already shown.
    private func waitForAnswer(_ key: @escaping () -> Void) {
        guard shownSequence != sequence else {
            key()
            return
        }
        waitingKey = key
        keyWaitTask?.cancel()
        keyWaitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.keyWait)
            guard !Task.isCancelled, let self else { return }
            runWaitingKey()
        }
    }

    func runWaitingKey() {
        keyWaitTask?.cancel()
        guard let key = waitingKey else { return }
        waitingKey = nil
        // A key that waited too long acts on what is shown, whatever it answers.
        shownSequence = sequence
        key()
    }

    // MARK: - Actions - Scopes

    /// Narrows the palette to `provider`: what the person types next searches it.
    func enter(_ provider: SearchProvider) {
        activeProvider = provider
        activeScope = nil
        narrowed()
    }

    /// Narrows the palette to `scope`'s kind of result.
    func enter(_ scope: PaletteScope) {
        activeScope = scope
        activeProvider = nil
        narrowed()
    }

    /// Leaves the search provider or scope, keeping what was typed.
    @discardableResult
    func leaveScope() -> Bool {
        guard !isUnscoped else { return false }
        activeProvider = nil
        activeScope = nil
        requestAnswer()
        replaceText?(query)
        return true
    }

    /// Enters what the text named in the palette's notation, keeping what
    /// followed it as what is typed.
    func enter(_ entry: PaletteEntry) {
        activeProvider = entry.provider
        activeScope = entry.scope
        narrowed(keeping: entry.text)
    }

    private func narrowed(keeping text: String = "") {
        invalidateURLCompletion()
        query = text
        replaceText?(text)
        requestAnswer()
    }
}
