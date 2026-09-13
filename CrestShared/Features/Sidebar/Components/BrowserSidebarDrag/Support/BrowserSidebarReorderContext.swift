/// Shared drag state and the collaborators authorized to commit its result.
@MainActor
struct BrowserSidebarReorderContext {
    let state: BrowserSidebarReorderState
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, state: BrowserSidebarReorderState) {
        self.state = state
        self.browser = browser
        self.spaceAccess = spaceAccess
    }

    func commit(_ target: BrowserSidebarReorderTarget, for item: BrowserSidebarReorderItem) {
        BrowserSidebarReorderCommit(browser: browser, spaceAccess: spaceAccess).apply(target, for: item)
    }
}
