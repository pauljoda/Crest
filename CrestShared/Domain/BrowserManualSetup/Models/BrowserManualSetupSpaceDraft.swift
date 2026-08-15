import Foundation

struct BrowserManualSetupSpaceDraft: Codable, Equatable, Identifiable, Sendable {
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
