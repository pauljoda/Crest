@MainActor
enum BrowserPlatformSidebarSelectionOrder {
    static func orderedItems(
        in browser: BrowserStore,
        assignment: BrowserSpaceRuntimeAssignment
    ) -> [BrowserSelectionItemID]? {
        nil
    }
}
