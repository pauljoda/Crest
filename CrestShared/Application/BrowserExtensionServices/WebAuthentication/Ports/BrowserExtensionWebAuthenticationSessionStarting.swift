import Foundation

/// The system authentication session, reduced to the one call Crest makes.
///
/// Keeping this seam framework-neutral lets the rules that surround a flow —
/// which callbacks are serviceable, whether the returned URL really is the
/// redirect that was awaited — stay in the Application layer and be tested
/// without presenting a window.
@MainActor
protocol BrowserExtensionWebAuthenticationSessionStarting: AnyObject {
    /// Presents the flow and resolves with the redirect the system captured.
    ///
    /// Throws ``BrowserExtensionWebAuthenticationError``.
    func start(
        authorizationURL: URL,
        callback: BrowserExtensionWebAuthenticationCallback,
        prefersEphemeralSession: Bool
    ) async throws -> URL
}
