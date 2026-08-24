import Foundation

struct BrowserSpace: Codable, Equatable, Identifiable, Sendable {
    static let maximumPinnedTabs = 12
    static let maximumFolderCount = 500
    static let maximumFolderDepth = 16

    let id: SpaceID
    let profile: BrowsingProfile
    var name: String
    var symbol: String
    var accent: SpaceAccent
    var branding: BrowserSpaceBranding
    var folders: [SavedFolder]
    var tabs: [BrowserTab]
    var splitGroups: [BrowserSplitGroupMetadata]
    var archivedTabs: [ArchivedTab]
    var history: [BrowserHistoryEntry]
    var browsingPreferences: BrowserSpaceBrowsingPreferences
    var credentialPreferences: BrowserCredentialPreferences
    var accessPolicy: BrowserSpaceAccessPolicy
    var isSavedTabsExpanded: Bool
    var savedTabsExpansionModifiedAt: Date?
    var selectedTabID: TabID?

    init(
        id: SpaceID,
        profile: BrowsingProfile,
        name: String,
        symbol: String,
        accent: SpaceAccent,
        branding: BrowserSpaceBranding? = nil,
        folders: [SavedFolder],
        tabs: [BrowserTab],
        splitGroups: [BrowserSplitGroupMetadata] = [],
        archivedTabs: [ArchivedTab] = [],
        history: [BrowserHistoryEntry] = [],
        browsingPreferences: BrowserSpaceBrowsingPreferences = .default,
        credentialPreferences: BrowserCredentialPreferences = .default,
        accessPolicy: BrowserSpaceAccessPolicy = .open,
        isSavedTabsExpanded: Bool = true,
        savedTabsExpansionModifiedAt: Date? = nil,
        selectedTabID: TabID?
    ) {
        self.id = id
        self.profile = profile
        self.name = name
        self.symbol = symbol
        self.accent = accent
        self.branding =
            branding?.normalized()
            ?? .legacy(accent: accent, symbol: symbol)
        self.folders = folders
        self.tabs = tabs
        self.splitGroups = BrowserSplitGroupMetadata.normalized(splitGroups)
        self.archivedTabs = archivedTabs
        self.history = history
        self.browsingPreferences = browsingPreferences
        self.credentialPreferences = credentialPreferences
        self.accessPolicy = accessPolicy
        self.isSavedTabsExpanded = isSavedTabsExpanded
        self.savedTabsExpansionModifiedAt = savedTabsExpansionModifiedAt
        self.selectedTabID = selectedTabID
    }

    var pinnedTabs: [BrowserTab] {
        tabs.filter { $0.placement == .pinned }
    }

    var savedTabs: [BrowserTab] {
        tabs.filter { $0.placement == .saved }
    }

    var currentTabs: [BrowserTab] {
        tabs.filter { $0.placement == .current }
    }

    var unfiledSavedTabs: [BrowserTab] {
        savedTabs.filter { $0.folderID == nil }
    }

    func savedTabs(in folderID: FolderID) -> [BrowserTab] {
        savedTabs.filter { $0.folderID == folderID }
    }

    var tabSections: BrowserTabSections {
        BrowserTabSections(tabs: tabs)
    }

    var folderTree: BrowserFolderTree {
        BrowserFolderTree(folders: folders)
    }

    func contains(_ tabID: TabID) -> Bool {
        tabs.contains { $0.id == tabID }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case profile
        case name
        case symbol
        case accent
        case branding
        case folders
        case tabs
        case splitGroups
        case archivedTabs
        case history
        case browsingPreferences
        case credentialPreferences
        case accessPolicy
        case isSavedTabsExpanded
        case savedTabsExpansionModifiedAt
        case selectedTabID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SpaceID.self, forKey: .id)
        profile = try container.decode(BrowsingProfile.self, forKey: .profile)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        // A palette this build has never heard of is a legacy tint, not a reason
        // to lose the Space. Branding carries the colors that are actually drawn.
        accent = container.decodeTolerantly(.accent, default: .indigo)
        branding =
            try container.decodeIfPresent(
                BrowserSpaceBranding.self,
                forKey: .branding
            ) ?? .legacy(accent: accent, symbol: symbol)
        folders = try container.decode([SavedFolder].self, forKey: .folders)
        tabs = try container.decode([BrowserTab].self, forKey: .tabs)
        splitGroups = BrowserSplitGroupMetadata.normalized(
            try container.decodeIfPresent(
                [BrowserSplitGroupMetadata].self,
                forKey: .splitGroups
            ) ?? []
        )
        archivedTabs = try container.decodeIfPresent([ArchivedTab].self, forKey: .archivedTabs) ?? []
        history = try container.decodeIfPresent([BrowserHistoryEntry].self, forKey: .history) ?? []
        browsingPreferences =
            try container.decodeIfPresent(
                BrowserSpaceBrowsingPreferences.self,
                forKey: .browsingPreferences
            ) ?? .default
        credentialPreferences =
            try container.decodeIfPresent(
                BrowserCredentialPreferences.self,
                forKey: .credentialPreferences
            ) ?? .default
        // Tolerance here needs two different defaults, which is why this reads the
        // term directly instead of going through `decodeTolerantly`. A Space
        // written before access policies existed stores no policy and is genuinely
        // `.open`. A *stored* policy this build cannot name was someone choosing
        // to restrict this Space, so it resolves to the guarded side: unlocking it
        // would be a real regression, while asking for a device unlock is
        // something its owner can always satisfy.
        let storedAccessPolicy = try? container.decodeIfPresent(
            String.self,
            forKey: .accessPolicy
        )
        accessPolicy =
            storedAccessPolicy
            .flatMap { $0 }
            .map { BrowserSpaceAccessPolicy(rawValue: $0) ?? .deviceOwnerAuthentication }
            ?? .open
        isSavedTabsExpanded =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .isSavedTabsExpanded
            ) ?? true
        savedTabsExpansionModifiedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .savedTabsExpansionModifiedAt
        )
        selectedTabID = try container.decodeIfPresent(TabID.self, forKey: .selectedTabID)
    }
}
