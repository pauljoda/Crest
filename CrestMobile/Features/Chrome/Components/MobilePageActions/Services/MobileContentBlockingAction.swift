@MainActor
struct MobileContentBlockingAction {
    private let browser: BrowserStore
    private let pageAssignment: () -> BrowserTabRuntimeAssignment?
    private let reconcile: (BrowserSession) async -> Void

    init(
        browser: BrowserStore,
        pages: any MobilePageActions
    ) {
        self.browser = browser
        pageAssignment = { pages.pageAssignment }
        reconcile = { session in
            await pages.reconcileContentBlocking(in: session)
        }
    }

    @discardableResult
    func perform() async -> Bool {
        guard let assignment = pageAssignment(),
            let space = browser.selectedSpace,
            let tab = browser.selectedTab,
            tab.id == assignment.tabID,
            space.id == assignment.spaceID,
            space.profile.id == assignment.profileID
        else { return false }
        var preferences = space.browsingPreferences
        preferences.contentBlockingPolicy =
            preferences.contentBlockingPolicy == .balanced ? .off : .balanced
        browser.updateBrowsingPreferences(preferences, in: space.id)
        let committedSession = browser.session
        await reconcile(committedSession)
        return true
    }
}
