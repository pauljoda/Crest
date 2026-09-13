import Observation

/// Routes settings through the measured layout while retaining its native-tab state.
@Observable @MainActor
final class MobileBrowserSettingsPresentation {
    private let browser: BrowserStore
    private let pages: MobileBrowserPageStore
    private let navigation: MobileBrowserNavigationState
    private let spaceAccess: BrowserSpaceAccessController
    private var presentation: BrowserTabActivationPolicy.SettingsPresentation?
    private var sheetAssignment: BrowserSpaceRuntimeAssignment?
    private var sheetTabID: TabID?
    private(set) var state = MobileBrowserSettingsState()
    private(set) var showsSheet = false

    init(
        browser: BrowserStore, pages: MobileBrowserPageStore,
        navigation: MobileBrowserNavigationState, spaceAccess: BrowserSpaceAccessController
    ) {
        self.browser = browser
        self.pages = pages
        self.navigation = navigation
        self.spaceAccess = spaceAccess
    }

    func destination(for tab: BrowserTab) -> BrowserTabActivationPolicy.Destination {
        BrowserTabActivationPolicy.destination(for: tab, settingsPresentation: presentation ?? .embedded)
    }

    func adapt(to layout: MobileBrowserPresentation) {
        reconcile()
        presentation = layout == .compact ? .sheet : .embedded
        if layout == .regular, showsSheet {
            let sheetState = state
            let source = sheetAssignment
            dismissSheet()
            guard let sheetAssignment = source,
                BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                    matching: sheetAssignment, in: browser, accessController: spaceAccess) != nil
            else { return }
            openEmbeddedSettings(adopting: sheetState)
        } else if layout == .regular,
            let space = browser.selectedSpace, !spaceAccess.isLocked(space),
            browser.selectedTab?.nativeContent == .settings
        {
            pages.select(session: browser.session)
        } else {
            routeSelectedSettingsAction()
        }
    }

    func open() {
        guard let presentation, let space = browser.selectedSpace, !spaceAccess.isLocked(space) else { return }
        switch presentation {
        case .embedded:
            openEmbeddedSettings()
        case .sheet:
            if let tab = space.tabs.first(where: { $0.nativeContent == .settings }) {
                guard let retained = retainedState(for: tab, in: space) else { return }
                state = retained
            } else if sheetAssignment != BrowserSpaceRuntimeAssignment(space: space) {
                state = MobileBrowserSettingsState()
            }
            presentSheet(in: space, tabID: space.tabs.first(where: { $0.nativeContent == .settings })?.id)
        }
    }

    @discardableResult
    func present(matching assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard let presentation,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID),
                in: browser, accessController: spaceAccess),
            let tab = space.tabs.first(where: { $0.id == assignment.tabID && $0.nativeContent == .settings })
        else { return false }
        switch presentation {
        case .embedded:
            browser.selectTab(tab.id)
            pages.select(session: browser.session)
            navigation.selectTab()
        case .sheet:
            guard let retained = retainedState(for: tab, in: space) else { return false }
            state = retained
            presentSheet(in: space, tabID: tab.id)
        }
        return true
    }

    @discardableResult
    func routeSelectedSettingsAction() -> Bool {
        guard presentation == .sheet,
            let space = browser.selectedSpace, !spaceAccess.isLocked(space),
            let tab = browser.selectedTab, tab.nativeContent == .settings
        else { return false }
        guard let retained = retainedState(for: tab, in: space) else { return false }
        state = retained
        browser.dismissNativeTab(tab.id, matching: BrowserSpaceRuntimeAssignment(space: space))
        pages.select(session: browser.session)
        presentSheet(in: space, tabID: tab.id)
        return true
    }

    @discardableResult
    func selectLiveSpace(_ id: SpaceID, matching source: BrowserTabRuntimeAssignment) -> Bool {
        guard presentation == .embedded,
            BrowserSettingsSpaceSelectionAction(browser: browser, spaceAccess: spaceAccess)
                .select(id, matching: source) != nil
        else { return false }
        synchronizeEmbeddedSettings()
        state.selection = .spaces
        return true
    }

    func reconcile() {
        guard showsSheet else { return }
        guard let sheetAssignment,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: sheetAssignment, in: browser, accessController: spaceAccess),
            sheetTabID == nil || space.tabs.contains(where: { $0.id == sheetTabID && $0.nativeContent == .settings })
        else {
            dismissSheet()
            return
        }
    }

    func dismissSheet() {
        showsSheet = false
        sheetAssignment = nil
        sheetTabID = nil
        state = MobileBrowserSettingsState()
    }

    private func presentSheet(in space: BrowserSpace, tabID: TabID?) {
        state.prepareForSheetPresentation()
        sheetAssignment = BrowserSpaceRuntimeAssignment(space: space)
        sheetTabID = tabID
        showsSheet = true
    }

    private func openEmbeddedSettings(adopting sheetState: MobileBrowserSettingsState? = nil) {
        guard browser.openSettings() != nil else { return }
        synchronizeEmbeddedSettings(adopting: sheetState)
    }

    private func synchronizeEmbeddedSettings(adopting sheetState: MobileBrowserSettingsState? = nil) {
        guard let space = browser.selectedSpace, let tab = browser.selectedTab else { return }
        guard let retained = retainedState(for: tab, in: space) else { return }
        state = retained
        if let sheetState, sheetState !== state {
            state.selection = sheetState.selection
            state.searchText = sheetState.searchText
            state.path = sheetState.path
        }
        state.prepareForEmbeddedPresentation()
        pages.select(session: browser.session)
        navigation.selectTab()
    }

    private func retainedState(for tab: BrowserTab, in space: BrowserSpace) -> MobileBrowserSettingsState? {
        pages.nativeTabs.load(tab: tab, space: space)
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        return pages.nativeTabs.runtime(matching: assignment, content: .settings)?
            .model(MobileBrowserSettingsState.self, make: MobileBrowserSettingsState.init)
    }
}
