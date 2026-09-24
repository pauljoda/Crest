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

    /// Commands that name one tab: `tab.delete`.
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

    /// `tab.icon`.
    struct TabIcon: Encodable, Sendable {
        let tabId: UUID
        let mode: TabIconMode
        let hasFavicon: Bool
        @BrowserCoreNullable var iconAccent: BrowserTabIconAccent?
        var emoji: String?
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
