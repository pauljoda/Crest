import Foundation
import SwiftUI

extension BrowserCommandPaletteModel {
    // MARK: - Actions - Answers

    /// The question for `text`, with the commands and settings pages this
    /// window offers, the suggestions fetched for the same text, the scope
    /// the person narrowed to, and whether the field may complete inline.
    func question(for text: String, remote: [String] = []) -> PaletteSuggestions {
        PaletteSuggestions(
            windowID: browser.windowID, text: text, commands: offeredCommands(for: text),
            settingsPages: commands?.settingsPages ?? [], remote: remote, provider: activeProvider?.seed,
            scope: activeScope, allowsCompletion: completionEditing.canPropose(for: text),
            pasteboard: text.isEmpty || text == openedWith ? pasteboard : nil)
    }

    /// The commands the core may rank for `text`. A palette without resting
    /// commands offers none while the text is blank, which the core reads as
    /// nothing typed.
    private func offeredCommands(for text: String) -> [PaletteCommand] {
        guard offersRestingCommands || !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return commands?.paletteCommands ?? []
    }

    /// Asks the core for the current query's answer off the main thread, then
    /// for the search suggestions the answer allows, and shows each only while
    /// no later keystroke has asked again.
    func requestAnswer() {
        sequence &+= 1
        let asked = sequence
        let question = question(for: query)
        let core = browser.core
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            guard let answer = await Self.answer(question, from: core), !Task.isCancelled, let self,
                asked == sequence
            else { return }
            show(answer, for: asked)
            guard let address = answer.suggestionAddress.flatMap(URL.init(string:)) else { return }
            do {
                try await Task.sleep(for: suggestionDebounce)
                let fetched = try await fetchSuggestions(address)
                try Task.checkCancellation()
                guard asked == sequence, !fetched.isEmpty,
                    let merged = await Self.answer(
                        PaletteSuggestions(
                            windowID: question.windowID, text: question.text, commands: question.commands,
                            settingsPages: question.settingsPages, remote: fetched, provider: question.provider,
                            scope: question.scope, allowsCompletion: question.allowsCompletion,
                            pasteboard: question.pasteboard),
                        from: core),
                    asked == sequence
                else { return }
                let selected = items.indices.contains(selectedResultIndex) ? items[selectedResultIndex].id : nil
                show(merged, for: asked)
                if let selected, let index = items.firstIndex(where: { $0.id == selected }) {
                    selectedResultIndex = index
                }
            } catch {
                // The local rows are already shown. Cancellation, a failed
                // fetch or an unreadable response leave them as they are.
            }
        }
    }

    func show(_ answer: PaletteAnswer, for asked: Int) {
        shownSequence = asked
        groups = BrowserCommandPaletteGroup.groups(of: answer)
        items = groups.flatMap(\.items)
        completionProposal = answer.completion
        offeredSearch = answer.offeredSearch
        matchingProviders = answer.matchingProviders
        offeredScope = answer.offeredScope
        if !items.indices.contains(selectedResultIndex) { selectedResultIndex = 0 }
        // A key waiting on this answer acts once the entry's own answer arrives.
        if asked == sequence, isUnscoped, let entry = answer.entry { enter(entry) }
        if asked == sequence, waitingKey != nil { runWaitingKey() }
    }

    /// The core's answer, ranked on a background thread.
    private nonisolated static func answer(_ question: PaletteSuggestions, from core: CrestCore) async -> PaletteAnswer?
    {
        await Task.detached(priority: .userInitiated) { try? core.query(question) }.value
    }
}
