import Foundation

enum BrowserCoreTabBatch {
    struct Response: Decodable {
        var error: String?
        var changes: [BrowserCoreSessionEditing.Result]?
        /// The follow-up selection for the window that ran the batch.
        var selection: BrowserSelectionHint?
    }

    static func arguments(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction,
        fallback: TabID?, follow: Bool, observations: [[String: Any]] = []) throws -> [String: Any] {
        func nullable(_ value: String?) -> Any { value as Any? ?? NSNull() }
        var arguments: [String: Any] = [
            "selection": [
                "roots": request.rootItems.map { item -> [String: Any] in
                    switch item {
                    case .tab(let id): ["id": id.rawValue.uuidString, "folder": false]
                    case .folder(let id): ["id": id.rawValue.uuidString, "folder": true]
                    }
                },
                "tabs": request.members.map { member -> [String: Any] in
                    ["id": member.id.rawValue.uuidString, "placement": member.placement.rawValue,
                     "folderId": nullable(member.folderID?.rawValue.uuidString),
                     "splitGroupId": nullable(member.splitGroupID?.rawValue.uuidString)]
                },
                "folders": request.folders.map { folder -> [String: Any] in
                    ["id": folder.id.rawValue.uuidString, "parentId": nullable(folder.parentID?.rawValue.uuidString),
                     "location": folder.location.rawValue]
                }
            ],
            "fallbackTabId": nullable(fallback?.rawValue.uuidString), "follow": follow,
            "copyObservations": observations, "folderColor": try BrowserCoreSync.value(BrowserSpaceBrandColor.folderDefault)
        ]
        switch action {
        case .file(let placement, let folder, let before, let beforeFolder):
            arguments.merge(["kind": "File", "placement": placement.rawValue,
                "folderId": nullable(folder?.rawValue.uuidString), "before": nullable(before?.rawValue.uuidString),
                "beforeFolderId": nullable(beforeFolder?.rawValue.uuidString)]) { _, new in new }
        case .newFolder(let location): arguments["kind"] = "NewFolder"; arguments["placement"] = location.rawValue
        case .newFolderAround(let id): arguments["kind"] = "NewFolderAround"; arguments["targetId"] = id.rawValue.uuidString
        case .moveToSpace(let destination):
            arguments["kind"] = "MoveToSpace"; arguments["destinationSpaceId"] = destination.spaceID.rawValue.uuidString
            arguments["destinationProfileId"] = destination.profileID.uuidString
        case .split(let target, let index):
            arguments["kind"] = "Split"; arguments["targetId"] = nullable(target?.rawValue.uuidString)
            arguments["index"] = index as Any? ?? NSNull()
        case .close: arguments["kind"] = "Close"
        case .delete: arguments["kind"] = "Delete"
        case .duplicate: arguments["kind"] = "Duplicate"
        case .keepLoaded(let value): arguments["kind"] = "KeepLoaded"; arguments["keep"] = value
        case .separateSplits: arguments["kind"] = "SeparateSplits"
        }
        return arguments
    }

    static func applying(_ response: Response, to session: BrowserSession) throws -> (session: BrowserSession, result: BrowserTabBatchResult) {
        if let error = response.error { throw batchError(error) }
        guard let changes = response.changes,
            response.selection?.spaceID.map({ id in session.spaces.contains { $0.id == id } }) != false
        else { throw BrowserTabBatchError.invalidDestination }
        var next = session
        let originals = Dictionary(uniqueKeysWithValues: session.spaces.flatMap(\.tabs).map { ($0.id, $0) })
        var copies: [(source: TabID, copy: TabID)] = []
        for var change in changes {
            guard let index = session.spaces.firstIndex(where: { $0.id == change.space.id }),
                session.spaces[index].profile == change.space.profile else { throw BrowserTabBatchError.staleSelection }
            let copied = Dictionary(uniqueKeysWithValues: change.copies.map { (TabID(rawValue: $0.copy), TabID(rawValue: $0.source)) })
            for i in change.space.tabs.indices {
                let id = change.space.tabs[i].id
                change.space.tabs[i].faviconData = originals[copied[id] ?? id]?.faviconData
            }
            for i in change.space.archivedTabs.indices {
                change.space.archivedTabs[i].tab.faviconData = originals[change.space.archivedTabs[i].id]?.faviconData
            }
            BrowserCoreSessionEditing.apply(change, to: &next, at: index)
            copies += change.copies.map { (TabID(rawValue: $0.source), TabID(rawValue: $0.copy)) }
        }
        return (next, BrowserTabBatchResult(copies: copies))
    }

    private static func batchError(_ code: String) -> BrowserTabBatchError {
        switch code {
        case "stale_selection", "unknown_tab", "unknown_folder", "unknown_space", "wrong_profile_identity", "space_deletion_in_progress": .staleSelection
        case "incomplete_split": .incompleteSplit
        case "pinned_capacity", "pinned_limit": .pinnedCapacity
        case "split_capacity", "split_limit": .splitCapacity
        case "folder_action_unavailable": .folderActionUnavailable
        case "cannot_pin_split": .cannotPinSplit
        case "cannot_move_split_across_spaces": .cannotMoveSplitAcrossSpaces
        case "current_tabs_only": .currentTabsOnly
        case "web_pages_only": .webPagesOnly
        default: .invalidDestination
        }
    }
}
