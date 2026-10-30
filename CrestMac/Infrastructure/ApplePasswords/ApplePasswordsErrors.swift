import Foundation

// MARK: - Unavailability

/// Why the helper cannot be used at all. Every case fails closed: Apple's own
/// extension stays the way to reach Apple Passwords.
enum ApplePasswordsUnavailability: Error, Equatable, Sendable {
    /// Crest does not run the helper in an isolated launch.
    case isolatedLaunch
    /// The native messaging manifest or the helper it names is not there.
    case helperMissing
    /// The helper is not a system component signed by Apple.
    case helperUntrusted
    case launchFailed
    /// The helper's input is closed: it ended before Crest finished writing.
    case pipeBroken
    /// The helper exited, or the system ended it. A launch the system refuses
    /// shows up here as a signal, because the kernel kills the helper.
    case terminated(status: Int32, endedBySignal: Bool)
    case unrecognizedCapabilities
    /// A frame or message was not what the protocol allows.
    case malformedReply
    /// A request went unanswered, so a late reply could be taken for another's.
    case timedOut
}

// MARK: - Pairing

enum ApplePasswordsPairingError: Error, Equatable, Sendable {
    /// The six-digit code does not match the challenge. The challenge is spent.
    case wrongCode
    /// There is no live challenge, or it is older than the code's lifetime.
    case challengeExpired
    /// The helper refused the challenge or the proof with this error code.
    case rejected(code: Int)
    /// The helper's final proof did not verify.
    case serverProofMismatch
    /// The helper's public value or salt is not acceptable.
    case invalidChallenge
    /// The code is not six digits. The challenge is kept, so the person can retype it.
    case malformedCode

    /// How the prompt carries on: the only place these errors meet its outcomes.
    var outcome: BrowserApplePasswordsPairingOutcome {
        switch self {
        case .wrongCode: return .wrongCode
        case .malformedCode: return .malformedCode
        case .challengeExpired: return .challengeExpired
        case .rejected, .serverProofMismatch, .invalidChallenge: return .failed
        }
    }
}

// MARK: - Requests

enum ApplePasswordsError: Error, Equatable, Sendable {
    case unavailable(ApplePasswordsUnavailability)
    /// The core does not allow the helper here: the status it answered does not start it.
    case notPermitted
    /// Only an https origin is queried.
    case insecureOrigin
    /// No paired session: the person has not entered a code, or the helper asked for a new one.
    case notPaired
    case queryFailed(ApplePasswordsQueryStatus)
    /// Apple Passwords has no password for that username on that host.
    case loginNotFound
    case malformedReply
    case cancelled
    /// The system could not supply random bytes, so no key or nonce can be made.
    case randomnessUnavailable
}
