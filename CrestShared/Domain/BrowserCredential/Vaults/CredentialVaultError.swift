import Foundation

enum CredentialVaultError: Error, Equatable, Sendable {
    case invalidOrigin
    case insecureOrigin
    case missingSpace
    case unavailableInPrivateBrowsing
    case credentialManagerDisabled
    case staleSaveCandidate
    case spaceMismatch(expected: UUID, actual: UUID)
    case malformedStoredCredential
    case atomicReplacementRestoreFailed
    case preferenceUpdateFailed
    /// The portable core could not answer a save decision. Nothing is saved.
    case saveDecisionUnavailable

    // MARK: - Initializers

    /// The error a use the core refused for `refusal` throws.
    init(_ refusal: CredentialRefusal) {
        self =
            refusal == .privateBrowsing
            ? .unavailableInPrivateBrowsing : refusal == .managerOff ? .credentialManagerDisabled : .insecureOrigin
    }
}
