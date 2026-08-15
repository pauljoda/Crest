@MainActor
final class MobileBrowserTransientPreviewAuthenticator: BrowserDeviceAuthenticating {
    private let authenticates: Bool

    init(authenticates: Bool = false) {
        self.authenticates = authenticates
    }

    func authenticate(reason _: String) async throws -> Bool {
        authenticates
    }
}
