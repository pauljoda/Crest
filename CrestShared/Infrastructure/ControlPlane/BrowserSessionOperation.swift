import Foundation

/// One command of the family's core session. Raw values are the core's
/// spellings in `SessionOperation.cs`.
enum BrowserSessionOperation: String, Codable, Sendable {
    case spaceBrowsingPreferences = "space.browsing_preferences"
    case spaceSearchProviderRemove = "space.search_provider.remove"
    case spaceSearchProviderUpsert = "space.search_provider.upsert"
    case tabTransfer = "tab.transfer"
    case tabsBatch = "tabs.batch"
    case workspaceImport = "workspace.import"
}
