import Foundation

struct BrowserSyncSpace: Codable, Equatable, Sendable {
    let id: SpaceID
    let profileID: UUID
    var name: String
    var symbol: String
    var accent: SpaceAccent
    var branding: BrowserSpaceBranding
    var browsingPreferences: BrowserSpaceBrowsingPreferences
    var accessPolicy: BrowserSpaceAccessPolicy
    var isSavedTabsExpanded: Bool
    var savedTabsExpansionModifiedAt: Date?
    /// `nil` means a client predating split-group customization wrote this
    /// payload and had no opinion. A new client writes an array, including an
    /// empty one when the last customized group was explicitly dissolved.
    var splitGroups: [BrowserSplitGroupMetadata]?
    var orderToken: String

    init(
        id: SpaceID,
        profileID: UUID,
        name: String,
        symbol: String,
        accent: SpaceAccent,
        branding: BrowserSpaceBranding? = nil,
        browsingPreferences: BrowserSpaceBrowsingPreferences = .default,
        accessPolicy: BrowserSpaceAccessPolicy = .open,
        isSavedTabsExpanded: Bool = true,
        savedTabsExpansionModifiedAt: Date? = nil,
        splitGroups: [BrowserSplitGroupMetadata]? = nil,
        orderToken: String
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.symbol = symbol
        self.accent = accent
        self.branding =
            branding?.normalized()
            ?? .legacy(accent: accent, symbol: symbol)
        self.browsingPreferences = browsingPreferences
        self.accessPolicy = accessPolicy
        self.isSavedTabsExpanded = isSavedTabsExpanded
        self.savedTabsExpansionModifiedAt = savedTabsExpansionModifiedAt
        self.splitGroups = splitGroups.map(BrowserSplitGroupMetadata.normalized)
        self.orderToken = orderToken
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID
        case name
        case symbol
        case accent
        case branding
        case browsingPreferences
        case accessPolicy
        case isSavedTabsExpanded
        case savedTabsExpansionModifiedAt
        case splitGroups
        case orderToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SpaceID.self, forKey: .id)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        accent = try container.decode(SpaceAccent.self, forKey: .accent)
        branding =
            try container.decodeIfPresent(
                BrowserSpaceBranding.self,
                forKey: .branding
            ) ?? .legacy(accent: accent, symbol: symbol)
        browsingPreferences =
            try container.decodeIfPresent(
                BrowserSpaceBrowsingPreferences.self,
                forKey: .browsingPreferences
            ) ?? .default
        accessPolicy =
            try container.decodeIfPresent(
                BrowserSpaceAccessPolicy.self,
                forKey: .accessPolicy
            ) ?? .open
        isSavedTabsExpanded =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .isSavedTabsExpanded
            ) ?? true
        savedTabsExpansionModifiedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .savedTabsExpansionModifiedAt
        )
        splitGroups = try container.decodeIfPresent(
            [BrowserSplitGroupMetadata].self,
            forKey: .splitGroups
        ).map(BrowserSplitGroupMetadata.normalized)
        orderToken = try container.decode(String.self, forKey: .orderToken)
    }
}
