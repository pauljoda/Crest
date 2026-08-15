import Foundation

/// Scripted authentication session for tests and previews.
///
/// A test sets ``outcome`` to the redirect or failure the system would have
/// produced, then asserts on what the service did with it — including the
/// arguments the session was started with, which are recorded verbatim.
@MainActor
final class InMemoryBrowserExtensionWebAuthenticationSession:
    BrowserExtensionWebAuthenticationSessionStarting
{
    /// What the next ``start(authorizationURL:callback:prefersEphemeralSession:)``
    /// resolves to.
    var outcome: Result<URL, BrowserExtensionWebAuthenticationError>

    private(set) var startedAuthorizationURLs: [URL] = []
    private(set) var startedCallbacks: [BrowserExtensionWebAuthenticationCallback] = []
    private(set) var startedEphemeralPreferences: [Bool] = []

    var startCount: Int { startedAuthorizationURLs.count }

    init(outcome: Result<URL, BrowserExtensionWebAuthenticationError>) {
        self.outcome = outcome
    }

    func start(
        authorizationURL: URL,
        callback: BrowserExtensionWebAuthenticationCallback,
        prefersEphemeralSession: Bool
    ) async throws -> URL {
        startedAuthorizationURLs.append(authorizationURL)
        startedCallbacks.append(callback)
        startedEphemeralPreferences.append(prefersEphemeralSession)
        return try outcome.get()
    }
}
