struct BrowserImportedPassword: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let sourceApplication: BrowserImportApplication
    let sourceProfileID: String
    let sourceProfileName: String
    let origin: CredentialOrigin
    let username: String
    let password: String

    var description: String {
        "BrowserImportedPassword(profile: \(sourceProfileID), origin: \(origin), username: <redacted>, password: <redacted>)"
    }

    var debugDescription: String { description }
}
