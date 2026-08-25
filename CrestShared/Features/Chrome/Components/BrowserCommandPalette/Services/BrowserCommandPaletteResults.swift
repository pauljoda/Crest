import Foundation

enum BrowserCommandPaletteResults {
    static func results(
        for input: BrowserCommandPaletteInput
    ) -> [BrowserCommandPaletteResult] {
        let query = BrowserCommandPaletteQuery(input.query)
        let intent = intentResult(
            query: query,
            searchProvider: input.searchProvider
        )

        var results: [BrowserCommandPaletteResult] = []
        results.reserveCapacity(BrowserCommandPaletteResultLimits.initialResultCapacity)

        if let intent {
            results.append(intent.result)
        }

        results.append(contentsOf: tabResults(query: query, input: input))
        guard !Task.isCancelled else { return [] }
        results.append(
            contentsOf: actionResults(
                query: query,
                commands: input.commands
            ))
        guard !Task.isCancelled else { return [] }
        results.append(contentsOf: savedResults(query: query, space: input.space))
        guard !Task.isCancelled else { return [] }

        var claimedURLs = Set<String>(
            minimumCapacity: (input.space?.tabs.count ?? 0) + 1
        )
        for tab in input.space?.tabs ?? [] {
            if let url = tab.url {
                claimedURLs.insert(normalizedKey(url))
            }
        }
        if let intent {
            claimedURLs.insert(normalizedKey(intent.url))
        }

        results.append(
            contentsOf: historyResults(
                query: query,
                space: input.space,
                claimedURLs: claimedURLs
            ))

        return results
    }
}

// MARK: - Remote Search Suggestions

extension BrowserCommandPaletteResults {
    static func insertingRemoteSuggestions(
        _ suggestions: [String],
        query: String,
        provider: BrowserSearchProvider,
        into localResults: [BrowserCommandPaletteResult]
    ) -> [BrowserCommandPaletteResult] {
        let normalizedQuery = normalizedSuggestion(query)
        var claimed = Set(
            localResults.map { normalizedSuggestion($0.title).lowercased() }
        )
        claimed.insert(normalizedQuery.lowercased())

        var remoteResults: [BrowserCommandPaletteResult] = []
        remoteResults.reserveCapacity(BrowserCommandPaletteResultLimits.searchSuggestions)
        for rawSuggestion in suggestions {
            guard remoteResults.count < BrowserCommandPaletteResultLimits.searchSuggestions else {
                break
            }
            let suggestion = normalizedSuggestion(rawSuggestion)
            guard !suggestion.isEmpty, suggestion.count <= 256 else { continue }
            let key = suggestion.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard claimed.insert(key).inserted else { continue }
            guard let url = provider.searchURL(for: suggestion) else { continue }
            remoteResults.append(
                BrowserCommandPaletteResult(
                    section: .searchSuggestions,
                    id: "search-suggestion-\(provider.id.rawValue)-\(key)",
                    title: suggestion,
                    subtitle: "Search with \(provider.title)",
                    symbol: "magnifyingglass",
                    searchProvider: provider,
                    trailing: "Search",
                    target: .url(url)
                )
            )
        }
        guard !remoteResults.isEmpty else { return localResults }

        let insertionIndex = localResults.first?.isIntent == true ? 1 : 0
        var results = localResults
        results.insert(contentsOf: remoteResults, at: insertionIndex)
        return results
    }

    private static func normalizedSuggestion(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

// MARK: - Intent

extension BrowserCommandPaletteResults {
    static func intentResult(
        query: BrowserCommandPaletteQuery,
        searchProvider: BrowserSearchProvider
    ) -> BrowserCommandPaletteIntentResult? {
        guard
            !query.isEmpty,
            let intent = AddressResolver.intent(
                query.text,
                searchProvider: searchProvider
            )
        else { return nil }

        switch intent {
        case .open(let url):
            let host =
                url.host()?.replacingOccurrences(of: "www.", with: "")
                ?? url.absoluteString
            return BrowserCommandPaletteIntentResult(
                result: BrowserCommandPaletteResult(
                    section: nil,
                    id: "intent-open",
                    title: "Open \(host)",
                    subtitle: url.absoluteString,
                    symbol: "globe",
                    trailing: "",
                    target: .url(url)
                ),
                url: url,
                isNavigation: true
            )
        case .search(let text, let provider, let url):
            return BrowserCommandPaletteIntentResult(
                result: BrowserCommandPaletteResult(
                    section: nil,
                    id: "intent-search",
                    title: "Search with \(provider.title)",
                    subtitle: text,
                    symbol: "magnifyingglass",
                    searchProvider: provider,
                    trailing: "",
                    target: .url(url)
                ),
                url: url,
                isNavigation: false
            )
        }
    }
}

// MARK: - Actions

extension BrowserCommandPaletteResults {
    static func actionResults(
        query: BrowserCommandPaletteQuery,
        commands: [BrowserShortcutCommand]
    ) -> [BrowserCommandPaletteResult] {
        let available = commands.filter { !excludedCommands.contains($0) }
        guard !available.isEmpty else { return [] }
        guard !query.isEmpty else {
            let resting = restingCommands.filter(available.contains)
            return resting.prefix(BrowserCommandPaletteResultLimits.restingActions)
                .map(actionResult)
        }
        return rank(
            available,
            limit: BrowserCommandPaletteResultLimits.matchedActions
        ) { command in
            BrowserCommandPaletteText.score(
                query,
                title: command.title,
                detail: command.section.title
            )
        }
        .map(actionResult)
    }

    static func actionResult(
        _ command: BrowserShortcutCommand
    ) -> BrowserCommandPaletteResult {
        BrowserCommandPaletteResult(
            section: .actions,
            id: "command-\(command.rawValue)",
            title: command.title,
            subtitle: command.section.title,
            symbol: command.paletteSymbol,
            trailing: "",
            target: .command(command)
        )
    }
}

// MARK: - Commands

extension BrowserCommandPaletteResults {
    static let restingCommands: [BrowserShortcutCommand] = [
        .newWindow,
        .reopenClosedTab,
        .showHistory,
        .showDownloads,
        .toggleSidebar,
    ]

    static let excludedCommands: Set<BrowserShortcutCommand> = [
        .newTab,
        .openLocation,
    ]
}

// MARK: - History

extension BrowserCommandPaletteResults {
    static func historyResults(
        query: BrowserCommandPaletteQuery,
        space: BrowserSpace?,
        claimedURLs: Set<String>
    ) -> [BrowserCommandPaletteResult] {
        guard !query.isEmpty, let history = space?.history, !history.isEmpty else {
            return []
        }

        var candidates:
            [(
                entry: BrowserHistoryEntry,
                score: Int,
                position: Int
            )] = []
        candidates.reserveCapacity(BrowserCommandPaletteResultLimits.historyCandidates)

        for (position, entry)
            in history
            .prefix(BrowserCommandPaletteResultLimits.historyScan)
            .enumerated()
        {
            guard !Task.isCancelled else { return [] }
            guard !claimedURLs.contains(normalizedKey(entry.url)) else { continue }
            guard
                let score = BrowserCommandPaletteText.score(
                    query,
                    title: entry.title,
                    detail: entry.url.absoluteString
                )
            else { continue }
            candidates.append(
                (
                    entry,
                    score + recencyBonus(position: position, entry: entry),
                    position
                ))
            if candidates.count >= BrowserCommandPaletteResultLimits.historyCandidates {
                break
            }
        }

        return
            candidates
            .sorted { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.position < rhs.position
                    : lhs.score > rhs.score
            }
            .prefix(BrowserCommandPaletteResultLimits.history)
            .map { candidate in
                BrowserCommandPaletteResult(
                    section: .history,
                    id: "history-\(candidate.entry.id.uuidString)",
                    title: candidate.entry.title.isEmpty
                        ? (candidate.entry.url.host()
                            ?? candidate.entry.url.absoluteString)
                        : candidate.entry.title,
                    subtitle: candidate.entry.url.absoluteString,
                    symbol: "clock",
                    trailing: "Open",
                    target: .url(candidate.entry.url)
                )
            }
    }

    static func recencyBonus(
        position: Int,
        entry: BrowserHistoryEntry
    ) -> Int {
        let recency = max(
            0,
            BrowserCommandPaletteResultLimits.maximumHistoryRecencyBonus
                - position
                / BrowserCommandPaletteResultLimits.historyRecencyDecayInterval
        )
        let repetition = min(
            BrowserCommandPaletteResultLimits.maximumHistoryRepetitionBonus,
            entry.visitCount * BrowserCommandPaletteResultLimits.historyVisitBonus
        )
        return recency + repetition
    }
}

// MARK: - Saved

extension BrowserCommandPaletteResults {
    static func savedResults(
        query: BrowserCommandPaletteQuery,
        space: BrowserSpace?
    ) -> [BrowserCommandPaletteResult] {
        guard !query.isEmpty, let space else { return [] }
        let tabs = space.tabs.filter { $0.placement != .current }
        let tree = space.folderTree
        let tabsByFolder = Dictionary(
            grouping: tabs.compactMap { tab in
                tab.folderID.map { ($0, tab) }
            }, by: \.0)

        var scored: [(BrowserCommandPaletteResult, Int)] = []
        for tab in tabs {
            guard !Task.isCancelled else { return [] }
            guard
                let score = BrowserCommandPaletteText.score(
                    query,
                    title: tab.displayTitle,
                    detail: tab.savedSiteURL?.absoluteString ?? tab.url?.absoluteString ?? ""
                )
            else { continue }
            scored.append(
                (
                    BrowserCommandPaletteResult(
                        section: .saved,
                        id: "saved-\(tab.id.id.uuidString)",
                        title: tab.displayTitle,
                        subtitle: savedSubtitle(for: tab, in: tree),
                        symbol: tab.placement == .pinned ? "pin.fill" : "bookmark",
                        trailing: "Switch to Tab",
                        target: .tab(
                            BrowserTabRuntimeAssignment(
                                tabID: tab.id,
                                spaceID: space.id,
                                profileID: space.profile.id
                            )
                        )
                    ),
                    score
                ))
        }

        for folder in tree.foldersInDisplayOrder {
            guard !Task.isCancelled else { return [] }
            guard
                let score = BrowserCommandPaletteText.score(
                    query,
                    title: folder.title,
                    detail: tree.pathTitle(for: folder.id) ?? ""
                )
            else { continue }
            let contents = tabsByFolder[folder.id, default: []].map { $0.1 }
            guard let first = contents.first else { continue }
            scored.append(
                (
                    BrowserCommandPaletteResult(
                        section: .saved,
                        id: "folder-\(folder.id.id.uuidString)",
                        title: folder.title,
                        subtitle: folderSubtitle(
                            count: contents.count,
                            path: tree.pathTitle(for: folder.id)
                        ),
                        symbol: folder.symbol,
                        trailing: "Open First Tab",
                        target: .tab(
                            BrowserTabRuntimeAssignment(
                                tabID: first.id,
                                spaceID: space.id,
                                profileID: space.profile.id
                            )
                        )
                    ),
                    score - BrowserCommandPaletteResultLimits.folderMatchPenalty
                ))
        }

        return
            scored
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 == rhs.element.1
                    ? lhs.offset < rhs.offset
                    : lhs.element.1 > rhs.element.1
            }
            .prefix(BrowserCommandPaletteResultLimits.saved)
            .map(\.element.0)
    }

    static func savedSubtitle(
        for tab: BrowserTab,
        in tree: BrowserFolderTree
    ) -> String {
        let host = tab.savedSiteURL?.host() ?? tab.url?.host() ?? ""
        guard let folderID = tab.folderID,
            let path = tree.pathTitle(for: folderID)
        else { return host }
        return host.isEmpty ? path : "\(path) · \(host)"
    }

    static func folderSubtitle(count: Int, path: String?) -> String {
        let tabs = count == 1 ? "1 tab" : "\(count) tabs"
        guard let path, path.contains("›") else { return tabs }
        return "\(path) · \(tabs)"
    }
}

// MARK: - Tabs

extension BrowserCommandPaletteResults {
    static func tabResults(
        query: BrowserCommandPaletteQuery,
        input: BrowserCommandPaletteInput
    ) -> [BrowserCommandPaletteResult] {
        guard let space = input.space else { return [] }
        let open = space.tabs.filter {
            $0.id != input.selectedTabID && !$0.isStartPage
        }
        guard !query.isEmpty else {
            return open.prefix(BrowserCommandPaletteResultLimits.restingTabs).map {
                tabResult($0, in: space, section: .tabs)
            }
        }
        let candidates = open.filter { $0.placement == .current }
        return rank(
            candidates,
            limit: BrowserCommandPaletteResultLimits.matchedTabs
        ) { tab in
            BrowserCommandPaletteText.score(
                query,
                title: tab.displayTitle,
                detail: tab.url?.absoluteString ?? ""
            )
        }
        .map { tabResult($0, in: space, section: .tabs) }
    }

    static func tabResult(
        _ tab: BrowserTab,
        in space: BrowserSpace,
        section: BrowserCommandPaletteSection
    ) -> BrowserCommandPaletteResult {
        BrowserCommandPaletteResult(
            section: section,
            id: "tab-\(tab.id.id.uuidString)",
            title: tab.displayTitle,
            subtitle: tab.url?.host() ?? tab.url?.absoluteString ?? "",
            symbol: "globe",
            trailing: "Switch to Tab",
            target: .tab(
                BrowserTabRuntimeAssignment(
                    tabID: tab.id,
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            )
        )
    }
}
