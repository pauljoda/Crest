import Foundation
import Observation
import SwiftUI

/// The shared palette's rows, keyboard selection and the search provider or
/// scope a person narrowed it to. The core ranks what the palette offers for each
/// query, off the main thread; an answer that arrives after a newer keystroke
/// is dropped, so the latest query always wins, and a key pressed before the
/// first answer for its text waits for it. The query text, the selection, the
/// completion editing and the modifier keys held stay here.
@MainActor
@Observable
final class BrowserCommandPaletteModel {
    // MARK: - Static Variables

    /// How long Return, Tab or Down wait for the answer to what was typed
    /// before they act on the rows already shown.
    static let keyWait: Duration = .milliseconds(300)

    // MARK: - Variables

    /// The window the palette speaks for, whose core answers it.
    let browser: BrowserStore
    /// The Space the palette speaks for, or nil when the window shows none.
    let space: SpaceModel?
    let selectedTabID: UUID?
    let commands: BrowserCommandPaletteCommandRegistry?
    /// Whether the palette offers the platform's resting commands before
    /// anything is typed. The Start Page's palette offers commands only once
    /// what is typed matches one.
    let offersRestingCommands: Bool

    var query: String {
        didSet {
            guard query != oldValue else { return }
            selectedResultIndex = 0
            requestAnswer()
        }
    }

    var groups: [BrowserCommandPaletteGroup] = []
    /// Every row, in the order the keyboard steps through them.
    var items: [BrowserCommandPaletteItem] = []
    var selectedResultIndex = 0
    var keyboardSelectionRevision = 0
    var completionEditing = BrowserURLCompletionEditingState()
    /// The search provider the person narrowed the palette to, or nil.
    var activeProvider: SearchProvider?
    /// The kind of result the person narrowed the palette to, or nil.
    var activeScope: PaletteScope?
    /// The modifier keys the person holds, which choose where a row opens.
    var heldModifiers: EventModifiers = []
    var completionProposal: AddressCompletion?
    var offeredSearch: SearchOffer?
    /// Every provider what is typed names or starts to name, closest first.
    var matchingProviders: [SearchProvider] = []
    var offeredScope: PaletteScope?
    @ObservationIgnored var applyCompletion: ((String, NSRange) -> Void)?
    /// Replaces the field's text, as entering or leaving a scope does.
    @ObservationIgnored var replaceText: ((String) -> Void)?

    /// Counts keystrokes: each query asks under the next number, and only the
    /// answer to the latest is shown.
    @ObservationIgnored var sequence = 0
    /// The keystroke whose answer the rows show.
    @ObservationIgnored var shownSequence = 0
    @ObservationIgnored var answerTask: Task<Void, Never>?
    /// A key pressed before the answer to what was typed arrived, and the
    /// wait that runs it on the rows already shown.
    @ObservationIgnored var waitingKey: (() -> Void)?
    @ObservationIgnored var keyWaitTask: Task<Void, Never>?
    /// The text on the pasteboard when the palette opened, offered with
    /// Paste and Go while the text is still what the palette opened with, or
    /// nil.
    @ObservationIgnored let pasteboard: String?
    /// What the field held when the palette opened: nothing for a new tab, or
    /// the address of the page the window shows.
    @ObservationIgnored let openedWith: String

    let suggestionDebounce: Duration
    let fetchSuggestions: @Sendable (URL) async throws -> [String]
    private let isSourceAvailableAction: (BrowserTabRuntimeAssignment) -> Bool
    let selectTabAction: (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool
    let openURLAction: (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool
    let dismissAction: () -> Void
    let emptySelectionActions: BrowserEmptySelectionPaletteActions?
    /// Where this platform can open a row, which the modifier keys choose among.
    let openings: [BrowserCommandPaletteOpening]

    /// How the person set the palette to rank and arrange its rows.
    var preferences: PalettePreferences { BrowserAppPreferenceStore.shared.preferences.palette }

    /// The search provider Tab enters for what is typed, or nil: one the
    /// text names exactly by its shortcut even while a completion shows, else
    /// one it names by title or site once no completion does.
    var providerOffer: SearchProvider? {
        guard isUnscoped, completionEditing.isAtEnd, preferences.searchesSitesWithTab, isCompletionSourceAvailable,
            let offer = offeredSearch, urlCompletion == nil || offer.beatsCompletion
        else { return nil }
        return offer.provider
    }

    /// The providers the palette offers as chips while what is typed is one
    /// word, closest first; none once the palette is narrowed.
    var providerChips: [SearchProvider] {
        guard isUnscoped, preferences.searchesSitesWithTab || preferences.providerSpaceTrigger.isEnabled,
            isCompletionSourceAvailable
        else { return [] }
        return matchingProviders
    }

    /// The scope Tab enters for what is typed, or nil.
    var scopeOffer: PaletteScope? {
        guard isUnscoped, completionEditing.isAtEnd, preferences.searchesSitesWithTab, urlCompletion == nil else {
            return nil
        }
        return offeredScope
    }

    var urlCompletion: AddressCompletion? {
        guard isUnscoped, isCompletionSourceAvailable, completionEditing.canPropose(for: query),
            completionProposal?.typed == query
        else { return nil }
        return completionProposal
    }

    var isCompletionSourceAvailable: Bool {
        if selectedTabID != nil { return availableSourceAssignment != nil }
        guard let space, let actions = emptySelectionActions,
            actions.source == BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        else { return false }
        return actions.isAvailable
    }

    /// Where Return opens the selected row while the person holds the keys
    /// they hold: `here` for a row that opens nothing, or keys that choose
    /// nothing.
    var selectedOpening: BrowserCommandPaletteOpening {
        guard items.indices.contains(selectedResultIndex) else { return .here }
        return opening(for: items[selectedResultIndex].row)
    }

    var isUnscoped: Bool { activeProvider == nil && activeScope == nil }

    var availableSourceAssignment: BrowserTabRuntimeAssignment? {
        guard let sourceAssignment, isSourceAvailableAction(sourceAssignment) else { return nil }
        return sourceAssignment
    }

    var sourceAssignment: BrowserTabRuntimeAssignment? {
        guard let space, let selectedTabID else { return nil }
        return BrowserTabRuntimeAssignment(tabID: selectedTabID, spaceID: space.id, profileID: space.profileID)
    }

    /// The New Tab surface's actions, when the palette opened over it in the
    /// Space it shows and it can act now.
    var availableEmptySelectionActions: BrowserEmptySelectionPaletteActions? {
        guard let actions = emptySelectionActions, let space,
            actions.source == BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID),
            actions.isAvailable
        else { return nil }
        return actions
    }

    // MARK: - Initializers

    init(
        browser: BrowserStore,
        space: SpaceModel?,
        selectedTabID: UUID?,
        initialQuery: String,
        commands: BrowserCommandPaletteCommandRegistry?,
        offersRestingCommands: Bool = true,
        suggestionDebounce: Duration = .milliseconds(250),
        fetchSuggestions: @escaping @Sendable (URL) async throws -> [String] = { address in
            try await BrowserSearchSuggestionClient.shared.suggestions(from: address)
        },
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab: @escaping (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool,
        dismiss: @escaping () -> Void,
        emptySelectionActions: BrowserEmptySelectionPaletteActions? = nil,
        openings: [BrowserCommandPaletteOpening] = [.here],
        readPasteboard: () -> String? = { nil }
    ) {
        self.browser = browser
        self.space = space
        self.selectedTabID = selectedTabID
        self.commands = commands
        self.offersRestingCommands = offersRestingCommands
        query = initialQuery
        self.suggestionDebounce = suggestionDebounce
        self.fetchSuggestions = fetchSuggestions
        isSourceAvailableAction = isSourceAvailable
        selectTabAction = selectTab
        openURLAction = openURL
        dismissAction = dismiss
        self.emptySelectionActions = emptySelectionActions
        self.openings = openings
        openedWith = initialQuery
        pasteboard = BrowserAppPreferenceStore.shared.preferences.palette.offers(.pasteAndGo) ? readPasteboard() : nil
        // The palette opens with its rows: the resting answer is quick to
        // rank, so it is asked for on the main thread.
        if let answer = try? browser.core.query(question(for: initialQuery)) { show(answer, for: sequence) }
    }
}
