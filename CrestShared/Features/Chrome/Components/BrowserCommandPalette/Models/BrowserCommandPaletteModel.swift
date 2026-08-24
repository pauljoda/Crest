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

    private let isPrivateBrowsing: Bool
    private let suggestionDebounce: Duration
    private let fetchSuggestions: @Sendable (String, BrowserSearchProvider) async throws -> [String]

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
        selectTabInSpace: (
            (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool
        )?,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL) -> Bool,
        dismiss: @escaping () -> Void
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
        query = initialQuery
        results = prepared.results
        resultGroups = prepared.groups
        publishedQuery = initialQuery
        self.isPrivateBrowsing = isPrivateBrowsing
        self.suggestionDebounce = suggestionDebounce
        self.fetchSuggestions = fetchSuggestions
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
        case .spaceTab(let assignment):
            guard
                let space = otherSpaces.first(where: {
                    assignmentMatches(assignment, space: $0)
                })
            else { return nil }
            return space.tabs.first { $0.id == assignment.tabID }
        case .url, .command:
            return nil
        }
    }

    func profileID(for result: BrowserCommandPaletteResult) -> UUID? {
        switch result.target {
        case .tab(let assignment), .spaceTab(let assignment):
            assignment.profileID
        case .url, .command:
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
            otherSpaces: otherSpaces,
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
