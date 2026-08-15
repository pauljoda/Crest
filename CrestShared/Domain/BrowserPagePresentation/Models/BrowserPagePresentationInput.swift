struct BrowserPagePresentationInput: Equatable, Sendable {
    let selection: BrowserPagePresentationSelection
    let hasActivePage: Bool
    let hasNavigationFailure: Bool
    let hasProcessFailure: Bool
    let unloadedBehavior: BrowserPageUnloadedBehavior
}
