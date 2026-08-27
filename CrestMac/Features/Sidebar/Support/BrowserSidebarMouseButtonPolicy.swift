enum BrowserSidebarMousePointerScope: Equatable {
    case webpage
    case sidebar
    case unowned
}

enum BrowserSidebarMouseButtonDisposition: Equatable {
    case navigatePage(BrowserSidebarMouseButtonAction)
    case switchSpace(BrowserSidebarMouseButtonAction)
    case consume
}

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

    static func disposition(
        for action: BrowserSidebarMouseButtonAction,
        pointerScope: BrowserSidebarMousePointerScope,
        canNavigatePage: Bool
    ) -> BrowserSidebarMouseButtonDisposition? {
        switch pointerScope {
        case .webpage:
            canNavigatePage ? .navigatePage(action) : .consume
        case .sidebar:
            .switchSpace(action)
        case .unowned:
            nil
        }
    }
}
