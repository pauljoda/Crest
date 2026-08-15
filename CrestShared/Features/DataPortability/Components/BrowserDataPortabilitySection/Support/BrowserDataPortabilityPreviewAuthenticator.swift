@MainActor
final class BrowserDataPortabilityPreviewAuthenticator:
    BrowserDeviceAuthenticating
{
    func authenticate(reason _: String) async throws -> Bool {
        true
    }
}
