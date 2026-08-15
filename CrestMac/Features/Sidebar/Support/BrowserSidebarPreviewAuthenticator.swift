import Foundation

final class BrowserSidebarPreviewAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason: String) async throws -> Bool {
        true
    }
}
