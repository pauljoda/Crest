enum BrowserSidebarMouseButtonPolicy {
    static func action(for buttonNumber: Int) -> BrowserSidebarMouseButtonAction? {
        switch buttonNumber {
        case 3:
            .previousSpace
        case 4:
            .nextSpace
        default:
            nil
        }
    }

    static func routesToPage(
        isOverWebView: Bool,
        canNavigatePage: Bool
    ) -> Bool {
        isOverWebView && canNavigatePage
    }
}
