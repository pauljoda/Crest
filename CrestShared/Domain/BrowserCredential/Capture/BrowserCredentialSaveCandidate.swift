import Foundation

/// A password stays only in process memory until the person accepts or dismisses
/// the native save/update prompt. This value is deliberately non-Codable and redacted.
struct BrowserCredentialSaveCandidate: Identifiable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    let id: UUID
    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let username: String
    let password: String
    let passwordKind: CredentialPasswordKind
    let isCrossOriginFrame: Bool
    let submittedAt: Date

    /// The form's current password, kept only for a password change that
    /// named no account, so the saved login holding it can name it.
    var currentPassword: String? = nil

    /// The saved login a password change was found to be for, which the save
    /// updates whatever other logins share its username.
    var accountID: UUID? = nil

    /// Whether the candidate still needs its account named, from the saved
    /// login that holds its current password.
    var needsAccount: Bool { currentPassword != nil }

    /// The same candidate for the saved login `account`, which it updates.
    func naming(_ account: CredentialDescriptor) -> BrowserCredentialSaveCandidate {
        BrowserCredentialSaveCandidate(
            id: id, origin: origin, topLevelOrigin: topLevelOrigin, username: account.username, password: password,
            passwordKind: passwordKind, isCrossOriginFrame: isCrossOriginFrame, submittedAt: submittedAt,
            accountID: account.id)
    }

    var description: String {
        "BrowserCredentialSaveCandidate(id: \(id), origin: \(origin), username: \(username), password: <redacted>)"
    }

    var debugDescription: String { description }
}
