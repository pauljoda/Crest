import Foundation

/// One `launchWebAuthFlow` run, as the capability broker resolved it.
///
/// Everything that confers authority is filled in by Crest from the loaded
/// extension context — the Space, the runtime id, and the redirect origin
/// derived from it. The extension supplies only the authorization URL and the
/// flow's shape.
struct BrowserExtensionWebAuthFlowRequest: Equatable, Sendable {
    let url: URL
    /// `https://<runtime id>.chromiumapp.org`, watched for as an origin.
    let redirectOrigin: String
    let isInteractive: Bool
    let abortsOnLoadForNonInteractive: Bool
    let nonInteractiveTimeout: TimeInterval
    let spaceID: SpaceID
    let extensionID: String
    let extensionDisplayName: String
}

/// Runs a web authorization flow in a Crest-owned web view.
///
/// This is a port because the flow needs a window and a web view, which the
/// shared layer has neither of. The host runs the navigation inside the
/// Space's own `WKWebsiteDataStore`, so the flow sees exactly the cookies the
/// person's own tabs see and a signed-in session refreshes silently.
///
/// The returned URL carries the authorization code. A conforming host must
/// never log it, trace it, or hand it anywhere but back to the calling
/// extension.
@MainActor
protocol BrowserExtensionWebAuthFlowHosting: AnyObject {
    func runWebAuthFlow(
        _ request: BrowserExtensionWebAuthFlowRequest
    ) async throws -> URL
}
