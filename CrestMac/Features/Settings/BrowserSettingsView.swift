import SwiftUI

struct BrowserSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.spaceContentIsInteractive) private var isActiveSpace
    let browser: BrowserStore
    let pages: BrowserPagePool
    let cloudSync: BrowserCloudSyncController
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let shortcuts: BrowserShortcutStore
    let onboardingCoordinator: BrowserOnboardingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState

    @Bindable var tabState: BrowserSettingsTabState
    let tabAssignment: BrowserTabRuntimeAssignment?

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        cloudSync: BrowserCloudSyncController,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        dataDeleter: (any BrowserSpaceDataDeleting)? = nil,
        shortcuts: BrowserShortcutStore,
        onboardingCoordinator: BrowserOnboardingCoordinator,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState =
            BrowserSpaceSettingsPresentationState(),
        tabState: BrowserSettingsTabState = BrowserSettingsTabState(),
        tabAssignment: BrowserTabRuntimeAssignment? = nil
    ) {
        self.tabState = tabState
        self.tabAssignment = tabAssignment
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
        HStack(spacing: 0) {
            BrowserSettingsSidebar(navigation: $tabState.navigation)
                .frame(width: 224)
            Divider()

            Group {
                // Inactive Spaces keep their Settings navigation, but don't lay
                // out an offscreen form for every live appearance update.
                if isActiveSpace {
                    BrowserSettingsDestinationPage(
                        destination: tabState.navigation.selection,
                        tabAssignment: tabAssignment,
                        browser: browser,
                        pages: pages,
                        cloudSync: cloudSync,
                        spaceAccess: spaceAccess,
                        dataDeleter: dataDeleter,
                        shortcuts: shortcuts,
                        onboardingCoordinator: onboardingCoordinator,
                        spaceSettingsPresentation: spaceSettingsPresentation,
                        searchText: $tabState.navigation.searchText
                    )
                    .id(tabState.navigation.selection)
                }
            }
            .frame(
                minWidth: 320,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(BrowserSettingsCanvas.background)
        .tint(CrestBrandTheme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.browserSettingsTabState, tabState)
        .environment(\.browserSettingsSelections, tabState.selections)
        .environment(\.browserSettingsIsTab, true)
        .environment(\.browserSettingsUsesLiveSidebar, true)
        .environment(
            \.browserSettingsSelectLiveSpace,
            BrowserSettingsLiveSpaceSelection { id in
                guard let space = browser.session.spaces.first(where: { $0.id == id }) else { return }
                spaceSettingsPresentation.present(assignment: BrowserSpaceRuntimeAssignment(space: space))
                browser.selectSpace(id)
                browser.openSettings()
                pages.select(session: browser.session)
            }
        )
        .onChange(of: scenePhase) { previousPhase, phase in
            lockPrivateSettings(previousPhase, phase)
        }
        .onChange(of: spaceSettingsPresentation.revision, initial: true) {
            _, revision in
            if let tabAssignment,
                spaceSettingsPresentation.requestedAssignment
                    != BrowserSpaceRuntimeAssignment(
                        spaceID: tabAssignment.spaceID, profileID: tabAssignment.profileID)
            {
                return
            }
            tabState.applyExternalRoute(
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
