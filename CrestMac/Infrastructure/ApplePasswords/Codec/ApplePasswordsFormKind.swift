import Foundation

/// The kind of form a saved login came from. Apple's extension names the kind
/// in the query identifier of a save, so each instance carries its own.
struct ApplePasswordsFormKind: Hashable, Sendable {
    // MARK: - Static Variables

    static let signIn = ApplePasswordsFormKind(queryID: .setPassword, capturedPasswordKind: .current)
    static let signUp = ApplePasswordsFormKind(queryID: .newAccount, capturedPasswordKind: .new)
    /// Crest's form detection cannot tell a change-password form from a sign-up
    /// form, so no captured password selects this kind yet.
    static let changePassword = ApplePasswordsFormKind(queryID: .changePassword, capturedPasswordKind: nil)

    private static let all = [signIn, signUp, changePassword]

    // MARK: - Variables

    /// The `QID` a save from this kind of form carries.
    let queryID: ApplePasswordsQueryID
    /// The kind of password field Crest captured from a form of this kind, if capture can tell.
    private let capturedPasswordKind: CredentialPasswordKind?

    // MARK: - Actions - Lookup

    /// The kind of form a captured password came from.
    static func capturing(_ passwordKind: CredentialPasswordKind) -> ApplePasswordsFormKind {
        all.first { $0.capturedPasswordKind == passwordKind } ?? .signIn
    }
}
