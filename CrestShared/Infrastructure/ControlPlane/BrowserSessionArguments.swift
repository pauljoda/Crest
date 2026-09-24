import Foundation

/// What a saved tab does with its saved address. Raw values are the core's
/// spellings in `SavedLocationAction.cs`.
enum BrowserSavedLocationAction: String, Encodable, Sendable {
    /// The saved address becomes the page the tab shows now.
    case replace
    /// The tab returns to its saved address.
    case restore
}

/// The `arguments` member of each session command, in the core's spelling.
/// Identities cross as plain UUIDs (the typed identifiers code as records), and
/// a member the core reads even without a value crosses as an explicit `null`.
enum BrowserSessionArguments {
    // MARK: - Tabs

    /// Commands that name one tab: `tab.delete`, `split.leave`,
    /// `archive.restore`.
    struct Tab: Encodable, Sendable {
        let tabId: UUID
    }

    /// `tab.open`.
    struct TabOpen: Encodable {
        let tab: BrowserTab
        @BrowserCoreNullable var index: Int?
        let select: Bool
        /// The tab a new tab opens after; the core keeps it outside that tab's split.
        var after: UUID?
    }

    /// `tab.close`.
    struct TabClose: Encodable, Sendable {
        let tabId: UUID
        let resetArchivePlacement: Bool
    }

    /// `tab.close_durable`.
    struct TabCloseDurable: Encodable, Sendable {
        let tabId: UUID
        let returnToSavedURL: Bool
    }

    /// `tab.observe`.
    struct TabObserve: Encodable, Sendable {
        let tabId: UUID
        @BrowserCoreNullable var url: String?
        @BrowserCoreNullable var title: String?
        let hasFavicon: Bool
        let faviconChanged: Bool
        @BrowserCoreNullable var iconAccent: BrowserTabIconAccent?
    }

    /// `tab.icon`.
    struct TabIcon: Encodable, Sendable {
        let tabId: UUID
        let mode: BrowserTabIconMode
        let hasFavicon: Bool
        @BrowserCoreNullable var iconAccent: BrowserTabIconAccent?
        var emoji: String?
    }

    /// `tab.favicon.cache`.
    struct TabFaviconCache: Encodable, Sendable {
        let tabId: UUID
        let url: String
        let hasFavicon: Bool
        @BrowserCoreNullable var iconAccent: BrowserTabIconAccent?
    }

    /// `tab.saved_location`.
    struct TabSavedLocation: Encodable, Sendable {
        let tabId: UUID
        let action: BrowserSavedLocationAction
    }

    /// `tab.rename`.
    struct TabRename: Encodable, Sendable {
        let tabId: UUID
        @BrowserCoreNullable var title: String?
    }

    /// `tab.residency`.
    struct TabResidency: Encodable, Sendable {
        let tabId: UUID
        let keep: Bool
    }

    /// `tab.move`.
    struct TabMove: Encodable, Sendable {
        let tabId: UUID
        let placement: TabPlacement
        @BrowserCoreNullable var folderId: UUID?
        @BrowserCoreNullable var before: UUID?
        let detach: Bool
    }

    /// The title and address a copy starts from, observed from its source page.
    struct CopyObservation: Encodable, Sendable {
        let tabId: UUID
        let title: String
        @BrowserCoreNullable var url: String?
    }

    /// `tab.copy`.
    struct TabCopy: Encodable, Sendable {
        let tabId: UUID
        let ids: [UUID]
        let copyObservations: [CopyObservation]
    }

    /// `tabs.file`.
    struct TabsFile: Encodable, Sendable {
        let tabIds: [UUID]
        let placement: BrowserFolderLocation
        @BrowserCoreNullable var folderId: UUID?
        @BrowserCoreNullable var before: UUID?
        @BrowserCoreNullable var beforeFolderId: UUID?
        let detach: Bool
    }

    // MARK: - Transient pages

    /// `transient.promote`.
    struct TransientPromote: Encodable {
        let requestId: UUID
        let sourceSpaceId: UUID
        let sourceProfileId: UUID
        @BrowserCoreNullable var leaseSpaceId: UUID?
        @BrowserCoreNullable var leaseProfileId: UUID?
        let sourceAccessible: Bool
        let destinationAccessible: Bool
        let supportsLiveAdoption: Bool
        @BrowserCoreNullable var tab: BrowserTab?
    }

    /// `transient.archive`.
    struct TransientArchive: Encodable {
        let requestId: UUID
        let tab: BrowserTab
    }

    // MARK: - Folders

    /// `folder.create`. Only the members a caller sets cross; `title` and
    /// `parentId` always do.
    struct FolderCreate: Encodable, Sendable {
        let folderId: UUID
        @BrowserCoreNullable var title: String?
        let placement: BrowserFolderLocation
        @BrowserCoreNullable var parentId: UUID?
        var color: BrowserSpaceBrandColor?
        var symbol: String?
        var tabIds: [UUID]?
        var detach: Bool?
    }

    /// `folder.delete`.
    struct Folder: Encodable, Sendable {
        let folderId: UUID
    }

    /// `folder.rename`.
    struct FolderRename: Encodable, Sendable {
        let folderId: UUID
        let title: String
    }

    /// `folder.collapse`.
    struct FolderCollapse: Encodable, Sendable {
        let folderId: UUID
        let collapsed: Bool
    }

    /// `folder.move`.
    struct FolderMove: Encodable, Sendable {
        let folderId: UUID
        @BrowserCoreNullable var parentId: UUID?
        @BrowserCoreNullable var beforeFolderId: UUID?
        @BrowserCoreNullable var before: UUID?
        @BrowserCoreNullable var placement: BrowserFolderLocation?
    }

    /// `folder.color` and `folder.symbol`.
    struct FolderValue<Value: Encodable>: Encodable {
        let folderId: UUID
        let value: Value
    }

    // MARK: - Splits

    /// `split.join`.
    struct SplitJoin: Encodable, Sendable {
        let tabId: UUID
        let targetId: UUID
        @BrowserCoreNullable var index: Int?
        let ids: [UUID]
        let copyObservations: [CopyObservation]
    }

    /// `split.reorder`: an explicit slot, or a step along the run.
    struct SplitReorder: Encodable, Sendable {
        let tabId: UUID
        var index: Int?
        var offset: Int?
    }

    /// `split.dissolve`.
    struct SplitGroup: Encodable, Sendable {
        let groupId: UUID
    }

    /// `split.move`.
    struct SplitMove: Encodable, Sendable {
        let groupId: UUID
        let placement: TabPlacement
        @BrowserCoreNullable var folderId: UUID?
        @BrowserCoreNullable var before: UUID?
    }

    /// `split.open_link`.
    struct SplitOpenLink: Encodable {
        let tab: BrowserTab
        let targetId: UUID
        let ids: [UUID]
        let copyObservations: [CopyObservation]
    }

    /// `split.title`, `split.icon` and `split.tint`; a `null` value clears it.
    struct SplitMetadata<Value: Encodable>: Encodable {
        let groupId: UUID
        @BrowserCoreNullable var value: Value?
    }

    // MARK: - History and records

    /// `history.visit`.
    struct HistoryVisit: Encodable, Sendable {
        let url: String
        @BrowserCoreNullable var title: String?
    }

    /// `history.remove_url`.
    struct HistoryRemoveURL: Encodable, Sendable {
        let url: String
    }

    /// `history.remove_range`, as reference-date seconds.
    struct HistoryRemoveRange: Encodable, Sendable {
        let start: TimeInterval
        let end: TimeInterval
    }

    // MARK: - Spaces

    /// Space commands that replace one stored value: `space.branding`,
    /// `space.access`, `space.browsing_preferences`,
    /// `space.credential_preferences` and `space.saved_expansion`.
    struct SpaceValue<Value: Encodable>: Encodable {
        let value: Value
    }

    /// `space.create` and `space.reset_private`: the native presentation
    /// defaults the new Space starts from.
    struct SpaceTemplate: Encodable {
        let template: BrowserSpace
    }

    /// `space.identity`.
    struct SpaceIdentity: Encodable, Sendable {
        let name: String
        let symbol: String
        let accent: SpaceAccent
    }

    /// `space.reorder`.
    struct SpaceReorder: Encodable, Sendable {
        let offsets: [Int]
        let destination: Int
    }

    /// `space.deletion.begin` and `space.remove`.
    struct SpaceDeletion: Encodable, Sendable {
        let operationID: UUID
    }

    /// `space.search_provider.upsert`.
    struct SearchProviderUpsert: Encodable, Sendable {
        let provider: BrowserCoreSearchProviderRecord
        let selects: Bool
    }

    /// `space.search_provider.remove`, with the engine's core identity.
    struct SearchProviderRemove: Encodable, Sendable {
        let id: String
    }
}
