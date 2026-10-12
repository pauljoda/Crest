import AppKit

extension BrowserMacAgents {
    // MARK: - Types

    private struct SpaceQuery: Decodable {
        let space: UUID?
    }

    private struct SpaceListing: Encodable {
        let id: UUID
        let name: String
        let locked: Bool
        let active: Bool?
        let symbol: String?
        let icon: String?
    }

    struct TabListing: Encodable {
        let id: UUID
        let space: UUID
        let title: String
        let url: String?
        let placement: String
        let isPinned: Bool
        let isSaved: Bool
        let folders: [String]
        let inUse: Bool
        let shown: Bool
    }

    // MARK: - Actions - Listings

    func listSpaces(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let reach = try reach(call)
        let workspace = reach.workspaceID.flatMap { core.state.workspaces[$0] }
        let selected = application.stackedWindowIDs.compactMap {
            application.windowCoordinator.existingModel(for: $0)
        }.first { !$0.isTemporary }?.browser.selectedSpaceID
        let spaces = reach.spaces.map { reached in
            let space = reached.isLocked ? nil : workspace?.spaces.model(reached.spaceID)
            return SpaceListing(
                id: reached.spaceID, name: reached.name, locked: reached.isLocked,
                active: space.map { $0.id == selected }, symbol: space?.settings.symbol,
                icon: space.flatMap(spaceIcon))
        }
        return .data(["spaces": spaces])
    }

    func listTabs(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let query = try call.arguments(SpaceQuery.self)
        let reach = try reach(call)
        var spaces = reach.spaces
        if let id = query.space {
            guard let space = spaces.first(where: { $0.spaceID == id }) else {
                throw .rejected(.agentSpaceUnavailable(AgentSpaceUnavailable(spaceID: id)))
            }
            spaces = [space]
        }
        let workspace = reach.workspaceID.flatMap { core.state.workspaces[$0] }
        let tabs = spaces.flatMap { space in
            space.tabs.map { describe($0, in: space.spaceID, model: workspace?.spaces.model(space.spaceID)) }
        }
        let locked = spaces.filter(\.isLocked).map(\.name)
        let note =
            locked.isEmpty
            ? nil : "Locked Spaces show no tabs until the person unlocks them: \(locked.joined(separator: ", "))."
        return .data(["tabs": tabs], note: note)
    }

    func listing(_ tabID: UUID, _ call: BrowserAgentCall) throws(BrowserAgentFailure) -> TabListing {
        let reach = try reach(call)
        let workspace = reach.workspaceID.flatMap { core.state.workspaces[$0] }
        for space in reach.spaces {
            if let tab = space.tabs.first(where: { $0.tabID == tabID }) {
                return describe(tab, in: space.spaceID, model: workspace?.spaces.model(space.spaceID))
            }
        }
        throw .rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: tabID)))
    }

    // MARK: - Actions - Descriptions

    private func describe(_ tab: AgentTab, in spaceID: UUID, model: SpaceModel?) -> TabListing {
        let folders = model.flatMap { space in space.tabs.model(tab.tabID).map { folderPath($0, in: space) } } ?? []
        return TabListing(
            id: tab.tabID, space: spaceID, title: tab.title, url: tab.url,
            placement: tab.placement.name, isPinned: tab.placement == .pinned, isSaved: tab.placement == .saved,
            folders: folders, inUse: tab.claimed,
            shown: application.stackedWindowIDs.contains {
                core.state.windows[$0]?.shownTabIDs.contains(tab.tabID) == true
            })
    }

    private func folderPath(_ tab: TabStateModel, in space: SpaceModel) -> [String] {
        var path: [String] = []
        var visited = Set<UUID>()
        var current = tab.folderID
        while let id = current, visited.insert(id).inserted, let folder = space.folders.model(id) {
            path.insert(folder.title, at: 0)
            current = folder.parentID
        }
        return path
    }

    private func spaceIcon(_ space: SpaceModel) -> String? {
        guard let image = BrowserSpaceSymbolArtworkRenderer.shared.menuImage(for: BrowserSpaceIdentity(space: space)),
            let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}
