/// Everything a sidebar row needs to take part in an in-place reorder: the live
/// drag state plus the collaborators used to commit the resulting move.
///
/// Passing this as one value keeps the drag-source signatures from growing a
/// parameter per collaborator, and makes reordering opt-in — call sites that
/// pass `nil` (mobile, previews) keep their existing drag behaviour.
@MainActor
struct BrowserSidebarReorderContext {
    let state: BrowserSidebarReorderState
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController
    ) {
        state = browser.sidebarReorderState
        self.browser = browser
        self.spaceAccess = spaceAccess
    }

    func commit(
        _ target: BrowserSidebarReorderTarget,
        for item: BrowserSidebarReorderItem
    ) {
        BrowserSidebarReorderCommit(
            browser: browser,
            spaceAccess: spaceAccess
        )
        .apply(target, for: item)
    }
}
