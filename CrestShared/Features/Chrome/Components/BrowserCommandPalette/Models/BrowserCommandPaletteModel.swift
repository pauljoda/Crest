import Foundation
import Observation

/// Owns query-derived results and keyboard selection for the shared palette.
@MainActor
@Observable
final class BrowserCommandPaletteModel {
    let space: BrowserSpace?
    let selectedTabID: TabID?
    let commands: BrowserCommandPaletteCommandRegistry?

    var query: String {
        didSet {
            guard query != oldValue else { return }
            selectedResultIndex = 0
            completionProposal =
                isCompletionSourceAvailable
                ? BrowserURLCompletion.proposal(query: query, space: space) : nil
            scheduleResultsRebuild()
        }
    }

    private var completionProposal: BrowserURLCompletion?
    private(set) var completionEditing = BrowserURLCompletionEditingState()
    @ObservationIgnored var applyCompletion: ((String, NSRange) -> Void)?

    var urlCompletion: BrowserURLCompletion? {
        guard isCompletionSourceAvailable, completionEditing.canPropose(for: query) else { return nil }
        return completionProposal
    }

    func updateCompletionEditing(text: String, selection: NSRange, isComposing: Bool) {
        completionEditing.update(text: text, selection: selection, isComposing: isComposing)
        if !isComposing { query = text }
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
        // Enter immediately after Tab must see the accepted URL intent even if
        // the asynchronous local-result rebuild has not been scheduled yet.
        if query == proposal.acceptedQuery {
            let prepared = BrowserCommandPaletteResultPreparation.prepare(for: input(query: query))
            publishedQuery = prepared.query
            results = prepared.results
            resultGroups = prepared.groups
            selectedResultIndex = 0
        }
        completionEditing.reject()
        return true
    }

    var isCompletionSourceAvailable: Bool {
        if selectedTabID != nil { return availableSourceAssignment != nil }
        guard let space, let actions = emptySelectionActions,
            actions.source == BrowserSpaceRuntimeAssignment(space: space)
        else { return false }
        return actions.isAvailable
    }

    private(set) var selectedResultIndex = 0
    private(set) var results: [BrowserCommandPaletteResult]
    private(set) var resultGroups: [BrowserCommandPaletteResultGroup]

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var publishedQuery: String

    private let isPrivateBrowsing: Bool
    private let suggestionDebounce: Duration
    private let fetchSuggestions: @Sendable (String, BrowserSearchProvider) async throws -> [String]

    private let isSourceAvailableAction: (BrowserTabRuntimeAssignment) -> Bool
    private let selectTabAction:
        (
            BrowserTabRuntimeAssignment,
            BrowserTabRuntimeAssignment
        ) -> Bool
    private let openURLAction: (BrowserTabRuntimeAssignment, URL) -> Bool
    private let dismissAction: () -> Void
    private let emptySelectionActions: BrowserEmptySelectionPaletteActions?

    init(
        space: BrowserSpace?,
        selectedTabID: TabID?,
        initialQuery: String,
        commands: BrowserCommandPaletteCommandRegistry?,
        isPrivateBrowsing: Bool = false,
        suggestionDebounce: Duration = .milliseconds(250),
        fetchSuggestions:
            @escaping @Sendable (
                String,
                BrowserSearchProvider
            ) async throws -> [String] = { query, provider in
                try await BrowserSearchSuggestionClient.shared.suggestions(
                    for: query,
                    provider: provider
                )
            },
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab:
            @escaping (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL) -> Bool,
        dismiss: @escaping () -> Void,
        emptySelectionActions: BrowserEmptySelectionPaletteActions? = nil
    ) {
        let input = BrowserCommandPaletteInput(
            query: initialQuery,
            space: space,
            selectedTabID: selectedTabID,
            commands: commands?.commands ?? [],
            searchProvider: space?.browsingPreferences.searchProvider ?? .google
        )
        let prepared = BrowserCommandPaletteResultPreparation.prepare(for: input)

        self.space = space
        self.selectedTabID = selectedTabID
        self.commands = commands
        query = initialQuery
        results = prepared.results
        resultGroups = prepared.groups
        publishedQuery = initialQuery
        self.isPrivateBrowsing = isPrivateBrowsing
        self.suggestionDebounce = suggestionDebounce
        self.fetchSuggestions = fetchSuggestions
        isSourceAvailableAction = isSourceAvailable
        selectTabAction = selectTab
        openURLAction = openURL
        dismissAction = dismiss
        self.emptySelectionActions = emptySelectionActions
    }

    func moveSelection(by offset: Int) {
        rejectURLCompletion()
        guard publishedQuery == query, !results.isEmpty else { return }
        selectedResultIndex = (selectedResultIndex + offset + results.count) % results.count
    }

    func selectResult(at index: Int) {
        rejectURLCompletion()
        guard publishedQuery == query, results.indices.contains(index) else { return }
        selectedResultIndex = index
    }

    func activateSelectedResult() {
        guard results.indices.contains(selectedResultIndex) else { return }
        activate(results[selectedResultIndex])
    }

    func activate(_ result: BrowserCommandPaletteResult) {
        guard publishedQuery == query else { return }

        if selectedTabID == nil {
            guard let actions = emptySelectionActions,
                let space,
                actions.source == BrowserSpaceRuntimeAssignment(space: space),
                actions.isAvailable
            else { return }
            let didActivate: Bool
            switch result.target {
            case .tab(let target): didActivate = actions.selectTab(target)
            case .url(let url): didActivate = actions.openURL(url)
            case .command(let command):
                commands?.perform(command)
                didActivate = commands != nil
            }
            if didActivate { dismiss() }
            return
        }

        let didActivate: Bool
        switch result.target {
        case .tab(let target):
            guard let sourceAssignment = availableSourceAssignment else { return }
            didActivate = selectTabAction(sourceAssignment, target)
        case .url(let url):
            guard let sourceAssignment = availableSourceAssignment else { return }
            didActivate = openURLAction(sourceAssignment, url)
        case .command(let command):
            guard availableSourceAssignment != nil else { return }
            commands?.perform(command)
            didActivate = commands != nil
        }
        if didActivate { dismiss() }
    }

    func dismiss() {
        dismissAction()
    }

    func waitForPendingResults() async {
        await rebuildTask?.value
    }

    func tab(for result: BrowserCommandPaletteResult) -> BrowserTab? {
        switch result.target {
        case .tab(let assignment):
            guard let space, assignmentMatches(assignment, space: space) else {
                return nil
            }
            return space.tabs.first { $0.id == assignment.tabID }
        case .url, .command:
            return nil
        }
    }

    func profileID(for result: BrowserCommandPaletteResult) -> UUID? {
        switch result.target {
        case .tab(let assignment):
            assignment.profileID
        case .url, .command:
            nil
        }
    }

    private func scheduleResultsRebuild() {
        rebuildTask?.cancel()
        let requestedQuery = query
        let input = input(query: requestedQuery)

        rebuildTask = Task { [weak self] in
            guard let self else { return }
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

            guard shouldRequestSuggestions(for: requestedQuery) else { return }
            do {
                try await Task.sleep(for: suggestionDebounce)
                try Task.checkCancellation()
                let provider = input.searchProvider
                let suggestions = try await fetchSuggestions(requestedQuery, provider)
                try Task.checkCancellation()
                guard query == requestedQuery, publishedQuery == requestedQuery else { return }

                let selectedID =
                    results.indices.contains(selectedResultIndex)
                    ? results[selectedResultIndex].id
                    : nil
                let merged = BrowserCommandPaletteResults.insertingRemoteSuggestions(
                    suggestions,
                    query: requestedQuery,
                    provider: provider,
                    into: prepared.results
                )
                results = merged
                resultGroups = BrowserCommandPaletteResultGroupingPolicy.groups(
                    results: merged,
                    query: requestedQuery
                )
                if let selectedID,
                    let index = merged.firstIndex(where: { $0.id == selectedID })
                {
                    selectedResultIndex = index
                }
            } catch {
                // Local results were already published. Cancellation, network
                // failure, and malformed responses intentionally degrade to them.
            }
        }
    }

    private func shouldRequestSuggestions(for query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 256 else { return false }
        guard !isPrivateBrowsing else { return false }
        guard space?.browsingPreferences.searchSuggestionsEnabled == true else {
            return false
        }
        return input(query: query).searchProvider.suggestionURL(for: query) != nil
    }

    private var availableSourceAssignment: BrowserTabRuntimeAssignment? {
        guard let sourceAssignment, isSourceAvailableAction(sourceAssignment)
        else {
            return nil
        }
        return sourceAssignment
    }

    private func input(query: String) -> BrowserCommandPaletteInput {
        BrowserCommandPaletteInput(
            query: query,
            space: space,
            selectedTabID: selectedTabID,
            commands: commands?.commands ?? [],
            searchProvider: space?.browsingPreferences.searchProvider ?? .google
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

enum BrowserSearchSuggestionResponseParser {
    static func suggestions(from data: Data) -> [String] {
        guard data.count <= BrowserSearchSuggestionClient.maximumResponseByteCount else {
            return []
        }
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [Any],
            payload.count >= 2,
            let values = payload[1] as? [Any]
        else { return [] }
        return values.compactMap { $0 as? String }.prefix(20).map { $0 }
    }
}

actor BrowserSearchSuggestionClient {
    static let shared = BrowserSearchSuggestionClient()
    static let maximumResponseByteCount = 64 * 1_024

    nonisolated static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return configuration
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: Self.sessionConfiguration)
    }

    func suggestions(
        for query: String,
        provider: BrowserSearchProvider
    ) async throws -> [String] {
        guard query.count <= 256, let url = provider.suggestionURL(for: query) else {
            return []
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard
            let response = response as? HTTPURLResponse,
            (200...299).contains(response.statusCode),
            response.expectedContentLength <= 0
                || response.expectedContentLength <= Self.maximumResponseByteCount
        else { return [] }

        var data = Data()
        data.reserveCapacity(min(Self.maximumResponseByteCount, 8 * 1_024))
        for try await byte in bytes {
            guard data.count < Self.maximumResponseByteCount else { return [] }
            data.append(byte)
        }
        return BrowserSearchSuggestionResponseParser.suggestions(from: data)
    }
}
