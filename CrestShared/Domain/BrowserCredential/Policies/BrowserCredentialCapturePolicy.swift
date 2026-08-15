import Foundation

enum BrowserCredentialCapturePolicy {
    static let candidateLifetime: TimeInterval = 45
    static let usernameHintLifetime: TimeInterval = 5 * 60

    static func accepts(
        frameOrigin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin
    ) -> Bool {
        frameOrigin.isSecure && topLevelOrigin.isSecure
    }

    static func offersSavedCredentials(for passwordKind: BrowserCredentialPasswordKind) -> Bool {
        passwordKind == .current
    }

    static func shouldOfferSave(
        candidate: BrowserCredentialSaveCandidate,
        hasVisiblePasswordField: Bool,
        now: Date = .now
    ) -> Bool {
        guard isCurrent(candidate, now: now) else { return false }
        return !hasVisiblePasswordField
    }

    static func isCurrent(
        _ candidate: BrowserCredentialSaveCandidate,
        now: Date = .now
    ) -> Bool {
        let age = now.timeIntervalSince(candidate.submittedAt)
        return age >= 0 && age <= candidateLifetime
    }

    static func username(
        from hint: BrowserCredentialUsernameHint,
        frameOrigin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        now: Date = .now
    ) -> String? {
        guard hint.origin == frameOrigin,
              hint.topLevelOrigin == topLevelOrigin,
              now.timeIntervalSince(hint.capturedAt) <= usernameHintLifetime else {
            return nil
        }
        return hint.username
    }
}
