import Foundation

/// A credential deliberately does not conform to `Codable`: passwords must never
/// enter the browser session JSON or a CloudKit record by accident.
struct BrowserCredential: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var descriptor: CredentialDescriptor
    var password: String

    var description: String {
        "BrowserCredential(descriptor: \(descriptor), password: <redacted>)"
    }

    var debugDescription: String { description }

    // MARK: - Actions - Moving

    /// The credential as the Space `spaceID` keeps it, with its identity and
    /// everything else unchanged.
    func moved(to spaceID: UUID) -> BrowserCredential {
        BrowserCredential(
            descriptor: CredentialDescriptor(
                id: descriptor.id, spaceID: spaceID, origin: descriptor.origin, scope: descriptor.scope,
                username: descriptor.username, displayName: descriptor.displayName, createdAt: descriptor.createdAt,
                updatedAt: descriptor.updatedAt, lastUsedAt: descriptor.lastUsedAt,
                isSynchronizable: descriptor.isSynchronizable),
            password: password)
    }
}
