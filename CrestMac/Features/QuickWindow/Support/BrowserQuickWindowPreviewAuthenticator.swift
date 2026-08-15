import Foundation

@MainActor
final class BrowserQuickWindowPreviewAuthenticator: BrowserDeviceAuthenticating {
    private let authenticates: Bool

    init(authenticates: Bool = false) {
        self.authenticates = authenticates
    }

    func authenticate(reason _: String) async throws -> Bool {
        authenticates
    }
}
