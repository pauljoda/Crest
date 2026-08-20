import SwiftUI

/// The desktop's settings detail column: one page of chrome around whichever
/// pane the shared router resolves.
///
/// Everything the desktop alone can offer is assembled here — the search field
/// the passwords pane filters by, the shortcut store, the extension controller
/// pool, and the setup actions that open the onboarding window — and handed to
/// ``BrowserSettingsDestinationRouter`` as data.
struct BrowserSettingsDestinationPage: View {
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

    var body: some View {
        BrowserSettingsPage(destination: destination) {
            BrowserSettingsDestinationRouter(
                destination: destination,
                browser: browser,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter,
                cloudSync: cloudSync,
                downloadCenter: pages.downloadCenter,
                permissionCenter: pages.permissionCenter,
                contentBlockingErrorDescription:
                    pages.contentBlockingErrorDescription,
                setupActions: setupActions,
                passwordLayout: .macOSPage,
                passwordSearchText: $searchText,
                extensionControllerPool: pages.extensionControllerPool,
                shortcuts: shortcuts,
                requestedSpaceID: requestedSpaceID,
                requestedExtensionCommand:
                    spaceSettingsPresentation.requestedExtensionCommand,
                requestRevision: spaceSettingsPresentation.revision
            )
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
