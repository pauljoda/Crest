@MainActor
final class MobileBrowserPreviewAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason _: String) async throws -> Bool {
        false
    }
}
