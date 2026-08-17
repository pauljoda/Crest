import SwiftUI

struct BrowserSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    let browser: BrowserStore
    let pages: BrowserPagePool
    let cloudSync: BrowserCloudSyncController
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let shortcuts: BrowserShortcutStore
    let onboardingCoordinator: BrowserOnboardingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState

    @State private var navigation = BrowserSettingsNavigationState()

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        cloudSync: BrowserCloudSyncController,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        dataDeleter: (any BrowserSpaceDataDeleting)? = nil,
        shortcuts: BrowserShortcutStore,
        onboardingCoordinator: BrowserOnboardingCoordinator,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState =
            BrowserSpaceSettingsPresentationState()
    ) {
        self.browser = browser
        self.pages = pages
        self.cloudSync = cloudSync
        self.spaceAccess = spaceAccess
        self.dataDeleter = dataDeleter ?? pages
        self.shortcuts = shortcuts
        self.onboardingCoordinator = onboardingCoordinator
        self.spaceSettingsPresentation = spaceSettingsPresentation
    }

    var body: some View {
        NavigationSplitView {
            BrowserSettingsSidebar(navigation: $navigation)
                .navigationSplitViewColumnWidth(
                    min: BrowserSettingsVisualPolicy.sidebarMinimumWidth,
                    ideal: BrowserSettingsVisualPolicy.sidebarIdealWidth,
                    max: BrowserSettingsVisualPolicy.sidebarMaximumWidth
                )
        } detail: {
            BrowserSettingsDestinationView(
                destination: navigation.selection,
                browser: browser,
                pages: pages,
                cloudSync: cloudSync,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter,
                shortcuts: shortcuts,
                onboardingCoordinator: onboardingCoordinator,
                spaceSettingsPresentation: spaceSettingsPresentation,
                searchText: $navigation.searchText
            )
            .id(navigation.selection)
            .frame(
                minWidth: BrowserSettingsChromePolicy.detailMinimumWidth,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: BrowserSettingsChromePolicy.minimumContentSize.width,
            idealWidth: BrowserSettingsChromePolicy.defaultContentSize.width,
            minHeight: BrowserSettingsChromePolicy.minimumContentSize.height,
            idealHeight: BrowserSettingsChromePolicy.defaultContentSize.height
        )
        .background(BrowserSettingsWindowSizingBridge())
        .onChange(of: scenePhase) { previousPhase, phase in
            lockPrivateSettings(previousPhase, phase)
        }
        .onChange(of: spaceSettingsPresentation.revision, initial: true) {
            _, revision in
            navigation.applyExternalRoute(
                spaceSettingsPresentation.requestedDestination,
                revision: revision
            )
        }
    }

    private func lockPrivateSettings(
        _ previousPhase: ScenePhase,
        _ phase: ScenePhase
    ) {
        guard phase != previousPhase else { return }

        switch phase {
        case .active:
            break
        case .inactive:
            spaceAccess.lockAllForInactiveScene()
        case .background:
            spaceAccess.lockAll()
        @unknown default:
            spaceAccess.lockAll()
        }
    }
}

#Preview {
    let browser = BrowserStore.preview()
    BrowserSettingsView(
        browser: browser,
        pages: BrowserPagePool(),
        cloudSync: BrowserCloudSyncController(browser: browser, configuration: nil),
        shortcuts: .inMemory(),
        onboardingCoordinator: BrowserOnboardingCoordinator()
    )
    .environment(BrowserWindowTransparencyPreviewFixture.makeStore())
    .environment(BrowserSplitFocusPreferenceStore.isolated())
}
