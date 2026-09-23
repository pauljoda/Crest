import Foundation

enum BrowserCoreTabBatch {
    // MARK: - Types

    /// The batch action the core applies. Raw values are the core's
    /// `TabBatchKind` spellings.
    enum Kind: String, Encodable, Sendable {
        case file = "File"
        case newFolder = "NewFolder"
        case newFolderAround = "NewFolderAround"
        case moveToSpace = "MoveToSpace"
        case split = "Split"
        case close = "Close"
        case delete = "Delete"
        case duplicate = "Duplicate"
        case keepLoaded = "KeepLoaded"
        case separateSplits = "SeparateSplits"
    }

    struct Response: Decodable {
        var error: BrowserCoreErrorCode?
        var changes: [BrowserCoreSessionEditing.Result]?
        /// The follow-up selection for the window that ran the batch.
        var selection: BrowserSelectionHint?
    }

    /// The `tabs.batch` arguments: the multi-selection as the window captured
    /// it, the action and the members that action reads.
    struct Arguments: Encodable {
        private enum CodingKeys: String, CodingKey {
            case selection
            case fallbackTabId
            case follow
            case copyObservations
            case folderColor
            case kind
            case placement
            case folderId
            case before
            case beforeFolderId
            case targetId
            case destinationSpaceId
            case destinationProfileId
            case index
            case keep
        }

        let request: BrowserTabBatchRequest
        let action: BrowserTabBatchAction
        let fallback: TabID?
        let follow: Bool
        let observations: [BrowserSessionArguments.CopyObservation]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Selection(request), forKey: .selection)
            try container.encode(fallback?.rawValue, forKey: .fallbackTabId)
            try container.encode(follow, forKey: .follow)
            try container.encode(observations, forKey: .copyObservations)
            try container.encode(BrowserSpaceBrandColor.folderDefault, forKey: .folderColor)
            switch action {
            case .file(let placement, let folder, let before, let beforeFolder):
                try container.encode(Kind.file, forKey: .kind)
                try container.encode(placement, forKey: .placement)
                try container.encode(folder?.rawValue, forKey: .folderId)
                try container.encode(before?.rawValue, forKey: .before)
                try container.encode(beforeFolder?.rawValue, forKey: .beforeFolderId)
            case .newFolder(let location):
                try container.encode(Kind.newFolder, forKey: .kind)
                try container.encode(location, forKey: .placement)
            case .newFolderAround(let id):
                try container.encode(Kind.newFolderAround, forKey: .kind)
                try container.encode(id.rawValue, forKey: .targetId)
            case .moveToSpace(let destination):
                try container.encode(Kind.moveToSpace, forKey: .kind)
                try container.encode(destination.spaceID.rawValue, forKey: .destinationSpaceId)
                try container.encode(destination.profileID, forKey: .destinationProfileId)
            case .split(let target, let index):
                try container.encode(Kind.split, forKey: .kind)
                try container.encode(target?.rawValue, forKey: .targetId)
                try container.encode(index, forKey: .index)
            case .close: try container.encode(Kind.close, forKey: .kind)
            case .delete: try container.encode(Kind.delete, forKey: .kind)
            case .duplicate: try container.encode(Kind.duplicate, forKey: .kind)
            case .keepLoaded(let value):
                try container.encode(Kind.keepLoaded, forKey: .kind)
                try container.encode(value, forKey: .keep)
            case .separateSplits: try container.encode(Kind.separateSplits, forKey: .kind)
            }
        }
    }

    /// The captured multi-selection: its root items, every member tab and
    /// every member folder.
    private struct Selection: Encodable {
        struct Root: Encodable {
            let id: UUID
            let folder: Bool
        }

        struct Tab: Encodable {
            let id: UUID
            let placement: TabPlacement
            @BrowserCoreNullable var folderId: UUID?
            @BrowserCoreNullable var splitGroupId: UUID?
        }

        struct Folder: Encodable {
            let id: UUID
            @BrowserCoreNullable var parentId: UUID?
            let location: BrowserFolderLocation
        }

        let roots: [Root]
        let tabs: [Tab]
        let folders: [Folder]

        init(_ request: BrowserTabBatchRequest) {
            roots = request.rootItems.map { item in
                switch item {
                case .tab(let id): Root(id: id.rawValue, folder: false)
                case .folder(let id): Root(id: id.rawValue, folder: true)
                }
            }
            tabs = request.members.map { member in
                Tab(
                    id: member.id.rawValue, placement: member.placement, folderId: member.folderID?.rawValue,
                    splitGroupId: member.splitGroupID?.rawValue)
            }
            folders = request.folders.map { folder in
                Folder(id: folder.id.rawValue, parentId: folder.parentID?.rawValue, location: folder.location)
            }
        }
    }

    // MARK: - Actions - Projection

    static func applying(_ response: Response, to session: BrowserSession) throws
        -> (session: BrowserSession, result: BrowserTabBatchResult)
    {
        if let error = response.error { throw batchError(error) }
        guard let changes = response.changes,
            response.selection?.spaceID.map({ id in session.spaces.contains { $0.id == id } }) != false
        else { throw BrowserTabBatchError.invalidDestination }
        var next = session
        let originals = Dictionary(uniqueKeysWithValues: session.spaces.flatMap(\.tabs).map { ($0.id, $0) })
        var copies: [(source: TabID, copy: TabID)] = []
        for var change in changes {
            guard let index = session.spaces.firstIndex(where: { $0.id == change.space.id }),
                session.spaces[index].profile == change.space.profile
            else { throw BrowserTabBatchError.staleSelection }
            let copied = Dictionary(
                uniqueKeysWithValues: change.copies.map { (TabID(rawValue: $0.copy), TabID(rawValue: $0.source)) })
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

    private static func batchError(_ code: BrowserCoreErrorCode) -> BrowserTabBatchError {
        switch code {
        case .staleSelection, .unknownTab, .unknownFolder, .unknownSpace, .wrongProfileIdentity,
            .spaceDeletionInProgress:
            .staleSelection
        case .incompleteSplit: .incompleteSplit
        case .pinnedCapacity, .pinnedLimit: .pinnedCapacity
        case .splitCapacity, .splitLimit: .splitCapacity
        case .folderActionUnavailable: .folderActionUnavailable
        case .cannotPinSplit: .cannotPinSplit
        case .cannotMoveSplitAcrossSpaces: .cannotMoveSplitAcrossSpaces
        case .currentTabsOnly: .currentTabsOnly
        case .webPagesOnly: .webPagesOnly
        default: .invalidDestination
        }
    }
}
