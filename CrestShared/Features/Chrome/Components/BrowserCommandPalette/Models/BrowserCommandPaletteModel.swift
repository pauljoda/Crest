import Foundation
import Observation

/// Owns query-derived results and keyboard selection for the shared palette.
@MainActor
@Observable
final class BrowserCommandPaletteModel {
    let space: BrowserSpace?
    let selectedTabID: TabID?
    let otherSpaces: [BrowserSpace]
    let commands: BrowserCommandPaletteCommandRegistry?
    /// Keyword providers eligible to take over the query. Nil leaves keyword
    /// mode switched off entirely.
    let omnibox: BrowserOmniboxRegistry?
    /// Where an accepted keyword suggestion opens, decided by how the palette
    /// was presented.
    let omniboxDisposition: BrowserOmniboxDisposition

    var query: String {
        didSet {
            guard query != oldValue else { return }
            selectedResultIndex = 0
            scheduleResultsRebuild()
        }
    }

    private(set) var selectedResultIndex = 0
    private(set) var results: [BrowserCommandPaletteResult]
    private(set) var resultGroups: [BrowserCommandPaletteResultGroup]

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var publishedQuery: String
    @ObservationIgnored private var activeOmniboxKeyword: BrowserOmniboxKeyword?

    private let isSourceAvailableAction: (BrowserTabRuntimeAssignment) -> Bool
    private let selectTabAction:
        (
            BrowserTabRuntimeAssignment,
            BrowserTabRuntimeAssignment
        ) -> Bool
    private let selectTabInSpaceAction:
        (
            (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool
        )?
    private let openURLAction: (BrowserTabRuntimeAssignment, URL) -> Bool
    private let dismissAction: () -> Void

    init(
        space: BrowserSpace?,
        selectedTabID: TabID?,
        initialQuery: String,
        otherSpaces: [BrowserSpace],
        commands: BrowserCommandPaletteCommandRegistry?,
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab:
            @escaping (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool,
        selectTabInSpace: (
            (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool
        )?,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL) -> Bool,
        dismiss: @escaping () -> Void,
        omnibox: BrowserOmniboxRegistry? = nil,
        omniboxDisposition: BrowserOmniboxDisposition = .currentTab
    ) {
        let actionableOtherSpaces = selectTabInSpace == nil ? [] : otherSpaces
        let input = BrowserCommandPaletteInput(
            query: initialQuery,
            space: space,
            selectedTabID: selectedTabID,
            otherSpaces: actionableOtherSpaces,
            commands: commands?.commands ?? [],
            searchProvider: space?.browsingPreferences.searchProvider ?? .google
        )
        let prepared = BrowserCommandPaletteResultPreparation.prepare(for: input)

        self.space = space
        self.selectedTabID = selectedTabID
        self.otherSpaces = actionableOtherSpaces
        self.commands = commands
        self.omnibox = omnibox
        self.omniboxDisposition = omniboxDisposition
        query = initialQuery
        results = prepared.results
        resultGroups = prepared.groups
        publishedQuery = initialQuery
        isSourceAvailableAction = isSourceAvailable
        selectTabAction = selectTab
        selectTabInSpaceAction = selectTabInSpace
        openURLAction = openURL
        dismissAction = dismiss
    }

    func moveSelection(by offset: Int) {
        guard publishedQuery == query, !results.isEmpty else { return }
        selectedResultIndex = (selectedResultIndex + offset + results.count) % results.count
    }

    func selectResult(at index: Int) {
        guard publishedQuery == query, results.indices.contains(index) else { return }
        selectedResultIndex = index
    }

    func activateSelectedResult() {
        guard results.indices.contains(selectedResultIndex) else { return }
        activate(results[selectedResultIndex])
    }

    func activate(_ result: BrowserCommandPaletteResult) {
        guard publishedQuery == query else { return }

        let didActivate: Bool
        switch result.target {
        case .tab(let target):
            guard let sourceAssignment = availableSourceAssignment else { return }
            didActivate = selectTabAction(sourceAssignment, target)
        case .spaceTab(let target):
            guard let sourceAssignment = availableSourceAssignment else { return }
            didActivate = selectTabInSpaceAction?(sourceAssignment, target) ?? false
        case .url(let url):
            guard let sourceAssignment = availableSourceAssignment else { return }
            didActivate = openURLAction(sourceAssignment, url)
        case .command(let command):
            guard availableSourceAssignment != nil else { return }
            commands?.perform(command)
            didActivate = commands != nil
        case .omniboxSuggestion(let acceptance):
            didActivate = acceptOmniboxSuggestion(acceptance)
        }
        if didActivate { dismiss() }
    }

    /// Removes a keyword suggestion from its provider's own history.
    ///
    /// Backs `chrome.omnibox.onDeleteSuggestion`. Rows that permit it offer the
    /// action in their context menu; a row whose provider did not mark it
    /// deletable is refused here as well as hidden there.
    @discardableResult
    func deleteOmniboxSuggestion(_ acceptance: BrowserOmniboxAcceptance) -> Bool {
        guard acceptance.isDeletable,
            let provider = omnibox?.provider(for: acceptance.keyword)
        else {
            return false
        }

        provider.deleteSuggestion(acceptance.content)
        scheduleResultsRebuild()
        return true
    }

    func dismiss() {
        dismissAction()
    }

    func tab(for result: BrowserCommandPaletteResult) -> BrowserTab? {
        switch result.target {
        case .tab(let assignment):
            guard let space, assignmentMatches(assignment, space: space) else {
                return nil
            }
            return space.tabs.first { $0.id == assignment.tabID }
        case .spaceTab(let assignment):
            guard
                let space = otherSpaces.first(where: {
                    assignmentMatches(assignment, space: $0)
                })
            else { return nil }
            return space.tabs.first { $0.id == assignment.tabID }
        case .url, .command, .omniboxSuggestion:
            return nil
        }
    }

    func profileID(for result: BrowserCommandPaletteResult) -> UUID? {
        switch result.target {
        case .tab(let assignment), .spaceTab(let assignment):
            assignment.profileID
        case .url, .command, .omniboxSuggestion:
            nil
        }
    }

    func foreignSpace(for result: BrowserCommandPaletteResult) -> BrowserSpace? {
        guard case .spaceTab(let assignment) = result.target else { return nil }
        return otherSpaces.first {
            assignmentMatches(assignment, space: $0)
        }
    }

    private func scheduleResultsRebuild() {
        rebuildTask?.cancel()
        let requestedQuery = query
        let resolution = omnibox?.resolve(requestedQuery)
        updateOmniboxSession(for: resolution?.input.keyword)

        rebuildTask = Task { [weak self] in
            // Keyword mode resolves its provider first: the rows it returns
            // replace every other source, so there is nothing to prepare until
            // the provider has answered.
            var context: BrowserCommandPaletteOmniboxContext?
            if let resolution {
                let suggestions = await resolution.provider.suggestions(
                    for: resolution.input.query
                )
                guard !Task.isCancelled else { return }
                let descriptor = resolution.provider.descriptor
                context = BrowserCommandPaletteOmniboxContext(
                    keyword: resolution.input.keyword,
                    query: resolution.input.query,
                    title: descriptor.title,
                    defaultSuggestionDescription: descriptor
                        .defaultSuggestionDescription,
                    suggestions: suggestions
                )
            }

            guard let self else { return }
            let input = self.input(query: requestedQuery, omnibox: context)
            let preparation = Task.detached(priority: .userInitiated) {
                BrowserCommandPaletteResultPreparation.prepare(for: input)
            }
            let prepared = await withTaskCancellationHandler {
                await preparation.value
            } onCancel: {
                preparation.cancel()
            }
            guard !Task.isCancelled else { return }
            guard query == prepared.query else { return }
            publishedQuery = prepared.query
            results = prepared.results
            resultGroups = prepared.groups
        }
    }

    /// Raises `onInputStarted` and `onInputCancelled` as the query crosses into
    /// and out of a provider's keyword.
    private func updateOmniboxSession(for keyword: BrowserOmniboxKeyword?) {
        guard keyword != activeOmniboxKeyword else { return }
        if let previous = activeOmniboxKeyword {
            omnibox?.provider(for: previous)?.inputCancelled()
        }
        activeOmniboxKeyword = keyword
        if let keyword {
            omnibox?.provider(for: keyword)?.inputStarted()
        }
    }

    private func acceptOmniboxSuggestion(
        _ acceptance: BrowserOmniboxAcceptance
    ) -> Bool {
        guard let provider = omnibox?.provider(for: acceptance.keyword) else {
            return false
        }
        provider.accept(acceptance.content, disposition: omniboxDisposition)
        activeOmniboxKeyword = nil
        return true
    }

    private var availableSourceAssignment: BrowserTabRuntimeAssignment? {
        guard let sourceAssignment, isSourceAvailableAction(sourceAssignment)
        else {
            return nil
        }
        return sourceAssignment
    }

    private func input(
        query: String,
        omnibox omniboxContext: BrowserCommandPaletteOmniboxContext? = nil
    ) -> BrowserCommandPaletteInput {
        BrowserCommandPaletteInput(
            query: query,
            space: space,
            selectedTabID: selectedTabID,
            otherSpaces: otherSpaces,
            commands: commands?.commands ?? [],
            searchProvider: space?.browsingPreferences.searchProvider ?? .google,
            omnibox: omniboxContext
        )
    }

    private var sourceAssignment: BrowserTabRuntimeAssignment? {
        guard let space, let selectedTabID else { return nil }
        return BrowserTabRuntimeAssignment(
            tabID: selectedTabID,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }

    private func assignmentMatches(
        _ assignment: BrowserTabRuntimeAssignment,
        space: BrowserSpace
    ) -> Bool {
        assignment.spaceID == space.id
            && assignment.profileID == space.profile.id
    }
}
