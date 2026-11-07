import Foundation

/// Turns blocking off, or on again, for the site of the page the window shows,
/// in its Space, and brings resident pages in line with it.
@MainActor
struct MobileContentBlockingAction {
    // MARK: - Variables

    private let browser: BrowserStore
    private let pageAssignment: () -> BrowserTabRuntimeAssignment?
    private let reconcile: () async -> Void
    private let reload: () -> Void
    /// What the shown page offers for blocking on its site, where its Space blocks.
    let siteSwitch: SiteContentBlockingSwitch?

    /// What the action says it does.
    var title: LocalizedStringResource { siteSwitch?.title ?? "Turn Off Blocking on This Site" }

    // MARK: - Initializers

    init(
        browser: BrowserStore,
        pages: any MobilePageActions
    ) {
        self.browser = browser
        pageAssignment = { pages.pageAssignment }
        reconcile = { await pages.reconcileContentBlocking() }
        reload = { pages.reload() }
        siteSwitch = SiteContentBlockingSwitch(
            core: browser.core, spaceID: browser.shownSpace?.id, url: pages.activePage?.webView.url)
    }

    // MARK: - Actions - Switching

    /// Switches the site while the page the action was built for is still the
    /// one the window shows, answering whether it did. The page reloads so the
    /// change shows.
    @discardableResult
    func perform() async -> Bool {
        guard let assignment = pageAssignment(), browser.shownTabAssignment == assignment,
            let siteSwitch, (try? browser.core.send(siteSwitch.intent)) != nil
        else { return false }
        await reconcile()
        reload()
        return true
    }
}
