enum BrowserPagePresentationSelection: Equatable, Sendable {
    case none
    case startPage
    case nativeContent
    case webPage
}

extension BrowserTab {
    var pagePresentationSelection: BrowserPagePresentationSelection {
        if nativeContent != nil { return .nativeContent }
        return isStartPage ? .startPage : .webPage
    }
}
