import Foundation

enum CredentialVaultError: Error, Equatable, Sendable {
    case invalidOrigin
    case insecureOrigin
    case missingSpace
    case unavailableInPrivateBrowsing
    case credentialManagerDisabled
    case staleSaveCandidate
    case spaceMismatch(expected: SpaceID, actual: SpaceID)
    case malformedStoredCredential
    case atomicReplacementRestoreFailed
}
