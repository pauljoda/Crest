import SwiftUI

/// Touch's settings detail: the shared router's pane as it comes, with the
/// sheet the password manager lives in hung off it.
///
/// Touch has no extensions surface and no rebindable command table, so it hands
/// the router neither an extension controller pool nor a shortcut store; those
/// two destinations stay out of its list and resolve to nothing here.
struct MobileBrowserSettingsDestinationPage: View {
    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @Environment(\.dismiss) private var dismiss
    @Environment(BrowserCloudSyncController.self) private var cloudSync
    @Environment(BrowserOnboardingCoordinator.self) private var onboardingCoordinator

    @State private var presentsPasswords = false

    var body: some View {
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
            passwordLayout: .mobilePage,
            showsMacOSImportRequirement: true,
            managePasswords: { presentsPasswords = true }
        )
        .sheet(isPresented: $presentsPasswords) {
            MobilePasswordSettingsView(
                browser: browser,
                spaceAccess: spaceAccess
            )
        }
    }

    private var setupActions: [BrowserAdvancedSetupAction] {
        [
            .init(
                id: "replay-setup",
                title: "Review Crest Setup",
                symbol: "sparkles",
                identifier: "mobile-open-setup",
                action: openSetup
            )
        ]
    }

    private func openSetup() {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            onboardingCoordinator.presentOnMobile(.manualSetup)
        }
    }
}
