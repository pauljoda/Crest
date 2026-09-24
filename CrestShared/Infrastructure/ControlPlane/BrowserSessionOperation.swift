import Foundation

/// One command or read of the family's core session. Raw values are the core's
/// spellings in `SessionOperation.cs`. App-wide `preferences.*` commands have
/// their own request model, `BrowserAppPreferenceCommand`.
enum BrowserSessionOperation: String, Codable, Sendable {
    case launchPlan = "launch.plan"
    case spaceBrowsingPreferences = "space.browsing_preferences"
    case spaceSearchProviderRemove = "space.search_provider.remove"
    case spaceSearchProviderUpsert = "space.search_provider.upsert"
    case tabTransfer = "tab.transfer"
    case tabsBatch = "tabs.batch"
    case workspaceImport = "workspace.import"
}
