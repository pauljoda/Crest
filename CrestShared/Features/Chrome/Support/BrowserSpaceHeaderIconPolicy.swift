enum BrowserSpaceHeaderIconPolicy {
    static func showsDisclosure(isSavedTabsExpanded: Bool) -> Bool {
        !isSavedTabsExpanded
    }
}
