struct BrowserHTTPAuthenticationSaveRequest:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let protectionSpace: BrowserHTTPAuthenticationProtectionSpace
    let username: String
    let password: String
    let replacing: CredentialDescriptor?

    var description: String {
        "BrowserHTTPAuthenticationSaveRequest(protectionSpace: \(protectionSpace), username: \(username), password: <redacted>)"
    }

    var debugDescription: String { description }
}
