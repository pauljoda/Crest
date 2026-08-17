import SwiftUI

struct BrowserSettingsDestinationView: View {
    @Environment(\.openWindow) private var openWindow

    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let pages: BrowserPagePool
    let cloudSync: BrowserCloudSyncController
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let shortcuts: BrowserShortcutStore
    let onboardingCoordinator: BrowserOnboardingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    @Binding var searchText: String

    @ViewBuilder
    var body: some View {
        switch destination {
        case .general:
            BrowserSettingsPage(destination: .general) {
                BrowserGeneralSettingsPane(browser: browser)
            }
        case .spaces:
            BrowserSettingsPage(
                destination: .spaces,
                scrollsContent: false,
                maximumContentWidth: .infinity,
                contentHorizontalPadding: 0,
                showsPageIdentity: false
            ) {
                BrowserSpaceSettingsView(
                    browser: browser,
                    spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter,
                    requestedSpaceID: requestedSpaceID,
                    requestRevision: spaceSettingsPresentation.revision
                )
            }
        case .sync:
            BrowserSettingsPage(destination: .sync) {
                BrowserSyncSettingsView(browser: browser, cloudSync: cloudSync)
            }
        case .links:
            BrowserSettingsPage(destination: .links) {
                BrowserLinkSettingsPane(
                    browser: browser,
                    spaceAccess: spaceAccess
                )
            }
        case .shortcuts:
            BrowserSettingsPage(destination: .shortcuts, scrollsContent: false) {
                BrowserShortcutSettingsView(
                    shortcuts: shortcuts,
                    browser: browser,
                    extensionControllerPool: pages.extensionControllerPool,
                    requestedSpaceID: requestedSpaceID,
                    requestedExtensionCommand:
                        spaceSettingsPresentation.requestedExtensionCommand,
                    requestRevision: spaceSettingsPresentation.revision
                )
            }
        case .privacy:
            BrowserSettingsPage(destination: .privacy) {
                BrowserPrivacySettingsPane(
                    browser: browser,
                    downloadCenter: pages.downloadCenter,
                    spaceAccess: spaceAccess,
                    permissionCenter: pages.permissionCenter,
                    contentBlockingErrorDescription:
                        pages.contentBlockingErrorDescription
                )
            }
        case .passwords:
            BrowserSettingsPage(destination: .passwords) {
                PasswordSettingsView(
                    browser: browser,
                    spaceAccess: spaceAccess,
                    searchText: $searchText
                )
            }
        case .extensions:
            BrowserSettingsPage(destination: .extensions) {
                BrowserExtensionSettingsPane(
                    browser: browser,
                    spaceAccess: spaceAccess,
                    extensionControllerPool: pages.extensionControllerPool,
                    requestedSpaceID: requestedSpaceID,
                    requestRevision: spaceSettingsPresentation.revision
                )
            }
        case .advanced:
            BrowserSettingsPage(destination: .advanced) {
                BrowserAdvancedSettingsPane(
                    browser: browser,
                    spaceAccess: spaceAccess,
                    setupActions: setupActions
                )
            }
        }
    }

    private var requestedSpaceID: SpaceID? {
        spaceSettingsPresentation.requestedSpaceID(in: browser)
    }

    private var setupActions: [BrowserAdvancedSetupAction] {
        [
            .init(
                id: "manual-setup",
                title: "Review & Customize Setup…",
                symbol: "sparkles",
                help: "Edit current Spaces or add Spaces and tabs in the setup preview"
            ) {
                presentSetup(.manualSetup)
            },
            .init(
                id: "import-browser",
                title: "Import from Another Browser…",
                symbol: "arrow.down.app",
                help: "Review another browser and merge selected tabs into your current Spaces"
            ) {
                presentSetup(.importBrowser)
            },
        ]
    }

    private func presentSetup(_ request: BrowserOnboardingRequest) {
        onboardingCoordinator.request = request
        openWindow(id: BrowserOnboardingCoordinator.sceneID)
        BrowserOnboardingWindowActivation.bringForward()
    }
}
