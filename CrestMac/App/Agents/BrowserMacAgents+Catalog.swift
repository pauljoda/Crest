import Foundation

extension BrowserMacAgents {
    // MARK: - Types

    private struct SearchQuery: Decodable {
        let space: UUID?
    }

    private struct SearchCatalog: Encodable {
        struct Provider: Encodable {
            let id: String
            let name: String
            let shortcuts: [String]
            let url: String
        }
        let providers: [Provider]
        let defaultProvider: Provider?
    }

    private struct HistoryQuery: Decodable {
        let query: String?
        let limit: Int?
        let domain: String?
    }

    private struct HistoryList: Encodable {
        struct Entry: Encodable {
            let id: UUID
            let space: UUID
            let spaceName: String
            let url: String
            let title: String
            let lastVisitedAt: String
            let lastVisitTime: Double
        }
        let entries: [Entry]
    }

    // MARK: - Actions - Search

    func listSearchProviders(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let query = try call.arguments(SearchQuery.self)
        let space = try resolveSpace(query.space, call)
        let catalog = BrowserSearchCatalog(core: core)
        func describe(_ provider: SearchProvider) -> SearchCatalog.Provider {
            .init(id: provider.name, name: provider.title, shortcuts: provider.shortcuts, url: provider.searchTemplate)
        }
        return .data(
            SearchCatalog(
                providers: catalog.providers.filter { catalog.isEnabled($0) }.map(describe),
                defaultProvider: catalog.provider(for: space.settings.browsingPreferences, isPrivate: false).map(
                    describe)))
    }

    // MARK: - Actions - History

    /// Reads live core history, filtering before the global cap; engine disk flushes are irrelevant.
    func searchHistory(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let query = try call.arguments(HistoryQuery.self)
        let limit = query.limit ?? 25
        guard (1...1000).contains(limit) else { throw .invalidArguments("limit must be between 1 and 1000.") }
        let reach = try reach(call)
        guard let workspaceID = reach.workspaceID, let workspace = core.state.workspaces[workspaceID] else {
            throw .rejected(.agentsOff(AgentsOff()))
        }
        let terms = (query.query ?? "").lowercased().split(whereSeparator: { $0.isWhitespace })
        let domain = query.domain?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = reach.spaces.filter { !$0.isLocked }.flatMap { reached -> [HistoryList.Entry] in
            guard let space = workspace.spaces.model(reached.spaceID) else { return [] }
            return space.history.entries.compactMap { entry in
                let text = (entry.url + " " + entry.title).lowercased()
                guard terms.allSatisfy({ text.contains($0) }) else { return nil }
                // Browser and extension pages are outside the agent's reach, even if persisted as history.
                guard let url = URL(string: entry.url), let scheme = url.scheme?.lowercased(),
                    scheme == "http" || scheme == "https", let host = url.host?.lowercased()
                else { return nil }
                if let domain, !domain.isEmpty {
                    let maps =
                        domain == "maps.google.com" && ["google.com", "www.google.com"].contains(host)
                        && (url.path == "/maps" || url.path.hasPrefix("/maps/"))
                    guard maps || host == domain || host.hasSuffix("." + domain) else { return nil }
                }
                return .init(
                    id: entry.id, space: space.id, spaceName: reached.name, url: entry.url,
                    title: entry.title,
                    lastVisitedAt: entry.lastVisitedAt.ISO8601Format(.init(includingFractionalSeconds: true)),
                    lastVisitTime: entry.lastVisitedAt.timeIntervalSince1970 * 1000)
            }
        }
        return .data(
            HistoryList(
                entries: Array(
                    entries.sorted {
                        if $0.lastVisitTime != $1.lastVisitTime { return $0.lastVisitTime > $1.lastVisitTime }
                        return $0.id.uuidString < $1.id.uuidString
                    }.prefix(limit))))
    }

    // MARK: - Actions - Spaces

    /// Uses only this session's current unlocked reach; locked names never grant a capability.
    func resolveSpace(_ id: UUID?, _ call: BrowserAgentCall) throws(BrowserAgentFailure) -> SpaceModel {
        let reach = try reach(call)
        let activeID = application.stackedWindowIDs.compactMap { application.windowCoordinator.existingModel(for: $0) }
            .first { !$0.isTemporary }?.browser.selectedSpaceID
        let available = reach.spaces.filter { !$0.isLocked }
        let reached =
            id.flatMap { requested in available.first { $0.spaceID == requested } }
            ?? (id == nil ? (available.first { $0.spaceID == activeID } ?? available.first) : nil)
        guard let reached, let workspaceID = reach.workspaceID,
            let space = core.state.workspaces[workspaceID]?.spaces.model(reached.spaceID)
        else { throw .refused("The opening Space is unavailable. Choose an allowed, unlocked Space.") }
        return space
    }
}
