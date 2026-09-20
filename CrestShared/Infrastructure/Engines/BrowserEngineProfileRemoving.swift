import Foundation

/// Erases a local engine profile after its native pages have been released.
/// Implementations also revoke engine-owned popups, background work and extensions.
@MainActor
protocol BrowserEngineProfileRemoving {
    func removeProfile(_ profile: BrowsingProfile, ephemeral: Bool) async throws
}
