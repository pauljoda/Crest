import Foundation

struct BrowserCredentialFillRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let usernameHint: String?
    let passwordKind: BrowserCredentialPasswordKind
    let isCrossOriginFrame: Bool
    let requestedAt: Date
}
