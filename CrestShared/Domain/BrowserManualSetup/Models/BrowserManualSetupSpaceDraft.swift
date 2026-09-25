import Foundation

struct BrowserManualSetupSpaceDraft: Equatable, Identifiable, Sendable {
    let id: SpaceID
    let profile: BrowsingProfile
    let isNew: Bool
    var existingPinnedTabCount: Int
    var customization: BrowserImportSpaceCustomization
    var addedTabs: [BrowserTab]

    init(space: BrowserSpace, isNew: Bool, addedTabs: [BrowserTab] = []) {
        id = space.id
        profile = space.profile
        self.isNew = isNew
        existingPinnedTabCount = isNew ? 0 : space.pinnedTabs.count
        customization = BrowserImportSpaceCustomization(space: space)
        self.addedTabs = addedTabs
    }
}

// MARK: - Codable

/// A manual setup in progress waits in the defaults, so its Space keeps the
/// stored identity spelling a build before S6.2 reads.
extension BrowserManualSetupSpaceDraft: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case profile
        case isNew
        case existingPinnedTabCount
        case customization
        case addedTabs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIdentity(forKey: .id)
        profile = try container.decode(BrowsingProfile.self, forKey: .profile)
        isNew = try container.decode(Bool.self, forKey: .isNew)
        existingPinnedTabCount = try container.decode(Int.self, forKey: .existingPinnedTabCount)
        customization = try container.decode(BrowserImportSpaceCustomization.self, forKey: .customization)
        addedTabs = try container.decode([BrowserTab].self, forKey: .addedTabs)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeStoredIdentity(id, forKey: .id)
        try container.encode(profile, forKey: .profile)
        try container.encode(isNew, forKey: .isNew)
        try container.encode(existingPinnedTabCount, forKey: .existingPinnedTabCount)
        try container.encode(customization, forKey: .customization)
        try container.encode(addedTabs, forKey: .addedTabs)
    }
}
