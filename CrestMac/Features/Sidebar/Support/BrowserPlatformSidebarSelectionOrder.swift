@MainActor
enum BrowserPlatformSidebarSelectionOrder {
    static func orderedItems(
        in browser: BrowserStore,
        assignment: BrowserSpaceRuntimeAssignment
    ) -> [BrowserSelectionItemID]? {
        BrowserNativeTabSelectionTarget.TargetView.orderedItems(browser: browser, assignment: assignment)
    }
}
