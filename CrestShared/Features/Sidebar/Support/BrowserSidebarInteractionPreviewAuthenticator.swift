@MainActor
final class BrowserSidebarInteractionPreviewAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason _: String) async throws -> Bool {
        true
    }
}
