import Observation

@Observable
@MainActor
final class BrowserWindowStateStore {
    private(set) var state: BrowserWindowState
    @ObservationIgnored private let persistence: any BrowserWindowStatePersisting

    var id: BrowserWindowID { state.id }
    var selectedSpaceID: SpaceID { state.selectedSpaceID }
    var sidebarWidth: Double? { state.sidebarWidth }
    var sidebarIsPresented: Bool? { state.sidebarIsPresented }

    /// Loads this window's own record. Without one, the window records what
    /// `browser` shows now; an older record without captured Spaces folds that
    /// selection in once.
    init(
        id: BrowserWindowID,
        browser: BrowserStore,
        persistence: any BrowserWindowStatePersisting
    ) {
        self.persistence = persistence
        let session = browser.session
        if var stored = persistence.load(id: id) {
            stored.foldLegacySelection(browser.selection, in: session)
            state = stored
        } else {
            state = BrowserWindowState(id: id, restoring: browser.selection, in: session)
        }
        state.repair(using: session)
        persistence.save(state)
    }

    func selectedSpace(in session: BrowserSession) -> BrowserSpace? {
        state.selectedSpace(in: session)
    }

    func selectedTab(in session: BrowserSession) -> BrowserTab? {
        state.selectedTab(in: session)
    }

    func selectSpace(_ spaceID: SpaceID, session: BrowserSession) {
        state.selectSpace(spaceID, session: session)
        persistence.save(state)
    }

    func selectTab(_ tabID: TabID, in spaceID: SpaceID, session: BrowserSession) {
        state.selectTab(tabID, in: spaceID, session: session)
        persistence.save(state)
    }

    func recordRenderedTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        session: BrowserSession
    ) {
        let previousState = state
        state.selectTab(tabID, in: spaceID, session: session)
        guard state != previousState else { return }
        persistence.save(state)
    }

    func captureSelection(of browser: BrowserStore) {
        let previousState = state
        state.captureSelection(browser.selection, in: browser.session)
        guard state != previousState else { return }
        persistence.save(state)
    }

    func captureSidebar(
        width: Double? = nil,
        isPresented: Bool? = nil
    ) {
        let previousState = state
        state.captureSidebar(width: width, isPresented: isPresented)
        guard state != previousState else { return }
        persistence.save(state)
    }

    func splitColumnFractions(for groupID: SplitGroupID) -> [Double]? {
        state.splitColumnFractions(for: groupID)
    }

    func captureSplitLayout(fractions: [Double], for groupID: SplitGroupID) {
        let previousState = state
        state.captureSplitLayout(fractions: fractions, for: groupID)
        guard state != previousState else { return }
        persistence.save(state)
    }



    func reconcile(with session: BrowserSession) {
        let previousState = state
        state.repair(using: session)
        guard state != previousState else { return }
        persistence.save(state)
    }

    func removePersistedState() {
        persistence.remove(id: id)
    }

    func flushPendingPersistence() async {
        await persistence.flushPendingSaves()
    }
}
