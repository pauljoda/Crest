import SwiftUI

/// The one place a settings destination becomes a pane.
///
/// Both shells navigate the same ``BrowserSettingsDestination`` catalog to the
/// same panes. What differs is the chrome around a pane and which destinations a
/// shell offers at all — neither is a reason for a second switch, so the shells
/// hand this router their inputs and decorate its output: the desktop wraps it
/// in a `BrowserSettingsPage`, touch shows it as it comes.
///
/// A destination a shell cannot host arrives here as absent data rather than as
/// a missing case. No extension controller pool means no Extensions pane, and no
/// shortcut store means no Shortcuts pane — the same answer
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
    /// Absent where the shell has no extensions surface.
    var extensionControllerPool: BrowserExtensionControllerPool? = nil
    /// Absent where the shell has no rebindable command table.
    var shortcuts: BrowserShortcutStore? = nil
    var requestedSpaceID: SpaceID? = nil
    var requestedExtensionCommand: BrowserExtensionCommandSettingsRoute? = nil
    var requestRevision = 0

    @ViewBuilder
    var body: some View {
        switch destination {
        case .general:
            BrowserGeneralSettingsPane(browser: browser)
        case .links:
            BrowserLinkSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess
            )
        case .shortcuts:
            if let shortcuts, let extensionControllerPool {
                BrowserPlatformShortcutSettingsPane(
                    shortcuts: shortcuts,
                    browser: browser,
                    extensionControllerPool: extensionControllerPool,
                    requestedSpaceID: requestedSpaceID,
                    requestedExtensionCommand: requestedExtensionCommand,
                    requestRevision: requestRevision
                )
            }
        case .spaces:
            BrowserPlatformSpaceSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter,
                requestedSpaceID: requestedSpaceID,
                requestRevision: requestRevision
            )
        case .sync:
            BrowserSyncSettingsView(browser: browser, cloudSync: cloudSync)
        case .privacy:
            BrowserPrivacySettingsPane(
                browser: browser,
                downloadCenter: downloadCenter,
                spaceAccess: spaceAccess,
                permissionCenter: permissionCenter,
                contentBlockingErrorDescription:
                    contentBlockingErrorDescription
            )
        case .passwords:
            BrowserPasswordSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                layout: passwordLayout,
                searchText: passwordSearchText,
                manage: managePasswords
            )
        case .extensions:
            if let extensionControllerPool {
                BrowserExtensionSettingsPane(
                    browser: browser,
                    spaceAccess: spaceAccess,
                    extensionControllerPool: extensionControllerPool,
                    requestedSpaceID: requestedSpaceID,
                    requestRevision: requestRevision
                )
            }
        case .advanced:
            BrowserAdvancedSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                setupActions: setupActions,
                showsMacOSImportRequirement: showsMacOSImportRequirement
            )
        }
    }
}
