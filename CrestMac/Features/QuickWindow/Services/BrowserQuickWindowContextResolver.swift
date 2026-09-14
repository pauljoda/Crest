@MainActor
struct BrowserQuickWindowContextResolver {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let pagePoolRegistry: BrowserPagePoolRegistry

    func context(
        for request: BrowserQuickWindowRequest
    ) -> BrowserQuickWindowBrowsingContext? {
        guard
            let context = context(
                targetWindowID: request.targetWindowID
            ),
            context.browser.space(matching: request.assignment) != nil
        else {
            return nil
        }
        return context
    }

    func context(
        targetWindowID: BrowserWindowID?
    ) -> BrowserQuickWindowBrowsingContext? {
        guard let targetWindowID else {
            return BrowserQuickWindowBrowsingContext(
                browser: browser,
                pages: pages,
                supportsLivePagePromotion: false
            )
        }
        guard let runtime = pagePoolRegistry.runtime(for: targetWindowID) else {
            return nil
        }
        // Blank windows own disposable tabs. A Quick Window opened from one
        // promotes into the shared workspace, never back into that blank window.
        if runtime.browser.isTemporaryWorkspace {
            return context(targetWindowID: nil)
        }
        return BrowserQuickWindowBrowsingContext(
            browser: runtime.browser,
            pages: runtime.pages,
            supportsLivePagePromotion: true
        )
    }
}
