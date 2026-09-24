import Foundation

/// One command or read of the family's core session. Raw values are the core's
/// spellings in `SessionOperation.cs`. App-wide `preferences.*` commands have
/// their own request model, `BrowserAppPreferenceCommand`.
enum BrowserSessionOperation: String, Codable, Sendable {
    case launchPlan = "launch.plan"
    case spaceAccess = "space.access"
    case spaceBranding = "space.branding"
    case spaceBrowsingPreferences = "space.browsing_preferences"
    case spaceCreate = "space.create"
    case spaceCredentialPreferences = "space.credential_preferences"
    case spaceDefault = "space.default"
    case spaceDeletionBegin = "space.deletion.begin"
    case spaceIdentity = "space.identity"
    case spaceRemove = "space.remove"
    case spaceReorder = "space.reorder"
    case spaceResetPrivate = "space.reset_private"
    case spaceSavedExpansion = "space.saved_expansion"
    case spaceSearchProviderRemove = "space.search_provider.remove"
    case spaceSearchProviderUpsert = "space.search_provider.upsert"
    case tabTransfer = "tab.transfer"
    case tabsBatch = "tabs.batch"
    case workspaceImport = "workspace.import"
}
