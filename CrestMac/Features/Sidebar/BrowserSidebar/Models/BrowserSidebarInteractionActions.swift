@MainActor
struct BrowserSidebarInteractionActions {
    let selectSpace: (SpaceID) -> Void
    let settleSpaceSelection: (SpaceID) -> Void
    let presentExtensions: (BrowserSpace) -> Void
    let presentSpaceSettings: (BrowserSpace) -> Void
    let createSpace: () -> Void
    let dismissUtilityOnBlankSpace: () -> Void
    let confirmClearHistory: (BrowserSpace) -> Void
    let handleAuxiliaryMouseAction:
        @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void
}
