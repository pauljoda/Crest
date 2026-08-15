import Foundation

struct CredentialKeychainItem: Equatable, Sendable {
    let account: String
    let metadata: Data
    let secret: Data
    let isSynchronizable: Bool
}
