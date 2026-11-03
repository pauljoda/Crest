import Foundation

/// Removes the stores WebKit's binding keeps for a profile when the core asks
/// it to erase the profile's data, whether or not any page of it opened.
@MainActor
protocol BrowserEngineProfileRemoving {
    func removeProfile(_ profileID: UUID, ephemeral: Bool) async throws
}
