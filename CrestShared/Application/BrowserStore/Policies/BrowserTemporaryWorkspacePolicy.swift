enum BrowserTemporaryWorkspacePolicy {
    static func borrowing(_ source: BrowserSpace, keeping local: BrowserSpace) -> BrowserSpace {
        var borrowed = source
        borrowed.folders = local.folders
        borrowed.tabs = local.tabs
        borrowed.splitGroups = local.splitGroups
        borrowed.archivedTabs = local.archivedTabs
        borrowed.history = local.history
        borrowed.isSavedTabsExpanded = local.isSavedTabsExpanded
        borrowed.savedTabsExpansionModifiedAt = local.savedTabsExpansionModifiedAt
        borrowed.selectedTabID = local.selectedTabID
        return borrowed
    }
}
