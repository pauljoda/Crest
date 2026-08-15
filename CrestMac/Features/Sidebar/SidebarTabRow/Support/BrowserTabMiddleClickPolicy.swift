enum BrowserTabMiddleClickPolicy {
    static func action(for placement: TabPlacement) -> BrowserTabMiddleClickAction {
        placement == .current ? .close : .unload
    }
}
