@MainActor
final class SpaceSwitcherPreviewAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason _: String) async throws -> Bool {
        false
    }
}
