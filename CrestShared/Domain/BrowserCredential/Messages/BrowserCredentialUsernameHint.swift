import Foundation

struct BrowserCredentialUsernameHint: Equatable, Sendable {
    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let username: String
    let capturedAt: Date
}
