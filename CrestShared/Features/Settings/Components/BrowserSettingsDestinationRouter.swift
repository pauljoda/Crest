import SwiftUI

/// Shows the pane a settings destination opens.
///
/// Both shells navigate the same ``BrowserSettingsDestination`` catalog to the
/// same panes. Each destination builds its own pane from the inputs this router
/// carries. What differs is the chrome around a pane and which destinations a
/// shell offers at all, so the shells hand this router their inputs and decorate
/// its output: the desktop wraps it in a `BrowserSettingsPage`, touch shows it as
/// it comes.
///
/// A destination a shell cannot host arrives here as absent data rather than as
/// a missing case. No shortcut store means no Shortcuts pane — the same answer
/// `BrowserPlatformSettingsDestinationCatalog` already gives the shells' lists.
struct BrowserSettingsDestinationRouter: View {
    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let cloudSync: BrowserCloudSyncController
    let downloadCenter: BrowserDownloadCenter
    let permissionCenter: BrowserSitePermissionCenter
    let contentBlockingErrorDescription: String?
    /// What this shell can offer a reader who wants to set Crest up again.
    let setupActions: [BrowserAdvancedSetupAction]
    /// How much of the passwords pane this shell puts on the page.
    let passwordLayout: BrowserPasswordSettingsLayout
    var showsMacOSImportRequirement = false
    /// The Settings window's own search field, for a shell that has one.
    var passwordSearchText: Binding<String> = .constant("")
    /// What a shell that keeps the password manager elsewhere does when the pane
    /// is asked for it.
    var managePasswords: (() -> Void)? = nil
    /// Absent where the shell has no rebindable command table.
    var shortcuts: BrowserShortcutStore? = nil
    var requestedSpaceID: UUID? = nil
    var requestRevision = 0
    /// The Space whose engine pages the feature flags pane shows, or nil
    /// while it is locked.
    var featureFlagsSpace: SpaceModel? = nil
    /// Opens Feature Flags from Advanced, for a shell that lists it there.
    var openFeatureFlags: (() -> Void)? = nil

    var body: some View {
        destination.pane(self)
    }
}
