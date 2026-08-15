@MainActor
final class PinnedTabGridPreviewAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason _: String) async throws -> Bool {
        true
    }
}
