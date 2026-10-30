import Foundation

/// The name an encrypted query carries in its envelope.
struct ApplePasswordsQueryID: Hashable, Sendable {
    // MARK: - Static Variables

    static let loginNames = ApplePasswordsQueryID(name: "CmdGetLoginNames4URL")
    static let password = ApplePasswordsQueryID(name: "CmdGetPassword4LoginName")
    static let oneTimeCodes = ApplePasswordsQueryID(name: "CmdGetOneTimeCodes")
    static let didFillOneTimeCode = ApplePasswordsQueryID(name: "CmdDidFillOneTimeCode")
    /// The save of a login from a sign-in form.
    static let setPassword = ApplePasswordsQueryID(name: "CmdSetPassword4LoginName_URL")
    /// The save of a login from a sign-up form.
    static let newAccount = ApplePasswordsQueryID(name: "CmdNewAccount4URL")
    /// The save of a login from a change-password form.
    static let changePassword = ApplePasswordsQueryID(name: "CmdChangePasswordForLoginName_URL")

    // MARK: - Variables

    let name: String

    // MARK: - Initializers

    private init(name: String) {
        self.name = name
    }
}
