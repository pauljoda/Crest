enum BrowserTabDismissalPolicy {
    static func action(
        for tab: BrowserTab?,
        tabCount: Int = 1
    ) -> BrowserTabDismissalAction {
        guard let tab else { return .closeWindow }
        switch tab.placement {
        case .pinned, .saved:
            return .unloadPage
        case .current:
            return tab.isStartPage && tabCount < 2 ? .closeWindow : .closeTab
        }
    }
}
