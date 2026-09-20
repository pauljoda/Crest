#if CREST_CHROMIUM_HOST
import Foundation

@MainActor
struct ChromiumProfileRemover: BrowserEngineProfileRemoving {
    let host: any CrestChromiumEngineHost

    func removeProfile(_ profile: BrowsingProfile, ephemeral: Bool) async throws {
        let deleted = await withCheckedContinuation { continuation in
            host.deleteProfile(profile.id.uuidString, ephemeral: ephemeral) { deleted in
                continuation.resume(returning: deleted)
            }
        }
        guard deleted else { throw RemovalError.failed }
    }

    private enum RemovalError: LocalizedError {
        case failed
        var errorDescription: String? { "Chromium couldn’t finish removing this Space’s browser data. Try again." }
    }
}
#endif
