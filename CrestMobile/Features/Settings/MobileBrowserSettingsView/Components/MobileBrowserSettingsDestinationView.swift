import SwiftUI

struct MobileBrowserSettingsDestinationView: View {
    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @Environment(\.dismiss) private var dismiss
    @Environment(BrowserCloudSyncController.self) private var cloudSync
    @Environment(BrowserOnboardingCoordinator.self) private var onboardingCoordinator

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
        case .spaces:
            MobileSpaceSettingsView(
                browser: browser,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter
            )
        case .sync:
            BrowserSyncSettingsView(browser: browser, cloudSync: cloudSync)
        case .privacy:
            BrowserPrivacySettingsPane(
                browser: browser,
                downloadCenter: pages.downloadCenter,
                spaceAccess: spaceAccess,
                permissionCenter: pages.permissionCenter,
                contentBlockingErrorDescription:
                    pages.contentBlockingErrorDescription
            )
        case .passwords:
            MobileCredentialSettingsView(
                browser: browser,
                spaceAccess: spaceAccess
            )
        case .advanced:
            BrowserAdvancedSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                setupActions: setupActions,
                showsMacOSImportRequirement: true
            )
        case .extensions, .shortcuts:
            EmptyView()
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

#Preview("Mobile General Settings") {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserSettingsDestinationView(
        destination: .general,
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        dataDeleter: fixture.pages
    )
    .environment(fixture.cloudSync)
    .environment(fixture.onboardingCoordinator)
}
