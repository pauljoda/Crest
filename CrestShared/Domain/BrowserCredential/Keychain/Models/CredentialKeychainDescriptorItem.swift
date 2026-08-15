import Foundation

struct CredentialKeychainDescriptorItem: Equatable, Sendable {
    let account: String
    let metadata: Data
    let isSynchronizable: Bool
}
