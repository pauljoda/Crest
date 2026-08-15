@MainActor
final class BrowserSettingsPrivateSpacePreviewAuthenticator:
    BrowserDeviceAuthenticating
{
    func authenticate(reason _: String) async throws -> Bool {
        false
    }
}
