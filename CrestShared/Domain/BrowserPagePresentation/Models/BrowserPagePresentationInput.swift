/// Encodes as the core's `page.presentation` request members.
struct BrowserPagePresentationInput: Encodable, Hashable, Sendable {
    let selection: BrowserPagePresentationSelection
    let hasActivePage: Bool
    let hasNavigationFailure: Bool
    let hasProcessFailure: Bool
    let unloadedBehavior: BrowserPageUnloadedBehavior
}
