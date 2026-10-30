import CryptoKit
import Foundation

/// A generated password that was sent to Apple Passwords before the form
/// submitted, remembered in memory for the page so the submission does not ask
/// to save it a second time. Only a digest of the password is kept, never the
/// password itself.
struct BrowserCredentialPresavedPassword: Equatable, Sendable {
    // MARK: - Variables

    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    /// The username Apple received with the password, empty when it got none.
    let username: String
    private let digest: Data

    // MARK: - Initializers

    init(origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, password: String, username: String) {
        self.origin = origin
        self.topLevelOrigin = topLevelOrigin
        self.username = username
        digest = Self.digest(of: password)
    }

    // MARK: - Actions - Matching

    /// Whether submitting `candidate` would only repeat what Apple already
    /// has. A submission that adds the username Apple was sent without is
    /// still worth offering, because Apple fills it in on an update, and so
    /// is one under a different username than the one Apple was sent.
    func covers(_ candidate: BrowserCredentialSaveCandidate) -> Bool {
        guard candidate.origin == origin, Self.digest(of: candidate.password) == digest else { return false }
        if username.isEmpty { return candidate.username.isEmpty }
        return candidate.username.isEmpty || candidate.username == username
    }

    private static func digest(of password: String) -> Data {
        Data(SHA256.hash(data: Data(password.utf8)))
    }
}
