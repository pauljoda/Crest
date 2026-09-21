import SwiftUI

struct BrowserSettingsDestinationPage: View {
    @Environment(\.openWindow) private var openWindow

    let destination: BrowserSettingsDestination
    var tabAssignment: BrowserTabRuntimeAssignment? = nil
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
                shortcuts: shortcuts,
                requestedSpaceID: requestedSpaceID,
                requestRevision: acceptsExternalRoute ? spaceSettingsPresentation.revision : 0
            )
        }
    }

    private var acceptsExternalRoute: Bool {
        guard let tabAssignment else { return true }
        return spaceSettingsPresentation.requestedAssignment
            == BrowserSpaceRuntimeAssignment(
                spaceID: tabAssignment.spaceID, profileID: tabAssignment.profileID)
    }

    private var requestedSpaceID: SpaceID? {
        acceptsExternalRoute ? spaceSettingsPresentation.requestedSpaceID(in: browser) : nil
    }

    private var setupActions: [BrowserAdvancedSetupAction] {
        [
            .init(
                id: "rerun-onboarding",
                title: "Rerun onboarding",
                symbol: "arrow.counterclockwise",
                help: "Restart setup from the welcome screen"
            ) {
                presentSetup(.rerun)
            },
            .init(
                id: "manual-setup",
                title: "Review & Customize Setup…",
                symbol: "sparkles",
                help: "Customize current Spaces or add new Spaces"
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
        if let host = BrowserMacWindowPresentation.host { host.openOnboardingWindow(request) }
        else { openWindow(id: BrowserOnboardingCoordinator.sceneID) }
        BrowserOnboardingWindowActivation.bringForward()
    }
}
