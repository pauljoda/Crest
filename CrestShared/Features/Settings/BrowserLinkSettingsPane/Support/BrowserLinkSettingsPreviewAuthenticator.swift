@MainActor
final class BrowserLinkSettingsPreviewAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason _: String) async throws -> Bool {
        true
    }
}
