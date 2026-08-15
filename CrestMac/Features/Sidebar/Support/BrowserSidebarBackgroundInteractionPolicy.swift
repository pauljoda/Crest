enum BrowserSidebarBackgroundInteractionPolicy {
    static let actions = BrowserSidebarBackgroundAction.allCases
    static let usesNativeWindowDragGesture = true
    static let limitsInteractionToUnoccupiedRemainder = true
}
