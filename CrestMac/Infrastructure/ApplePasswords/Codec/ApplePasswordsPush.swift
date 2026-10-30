import Foundation

/// Something the helper announces without being asked. The first two end the
/// paired session: the helper no longer holds the key it was paired with. A
/// one-time code arriving changes nothing about the session.
struct ApplePasswordsPush: Hashable, Sendable {
    // MARK: - Static Variables

    static let passwordsDisabled = ApplePasswordsPush(name: "passwordsDisabled", endsSession: true)
    static let reloginNeeded = ApplePasswordsPush(name: "reloginNeeded", endsSession: true)
    /// A code arrived. It carries nothing Crest reads.
    static let oneTimeCodeAvailable = ApplePasswordsPush(name: "oneTimeCodeAvailable", endsSession: false)

    // MARK: - Variables

    /// How the log names the push. Never a message's contents.
    let name: String
    /// Whether the helper no longer holds the session after announcing this.
    let endsSession: Bool

    // MARK: - Initializers

    private init(name: String, endsSession: Bool) {
        self.name = name
        self.endsSession = endsSession
    }
}
