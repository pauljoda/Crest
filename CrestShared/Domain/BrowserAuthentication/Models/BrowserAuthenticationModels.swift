struct BrowserAuthenticationChallenge: Equatable, Sendable {
    let authenticationMethod: BrowserAuthenticationMethod
    let isProxy: Bool
    let previousFailureCount: Int
    let protectionSpace: BrowserHTTPAuthenticationProtectionSpace?
    let descriptor: BrowserHTTPAuthenticationDescriptor
    let proposedUsername: String?
}

enum BrowserAuthenticationHandling: Equatable {
    case promptForCredentials
    case performDefaultHandling
    case cancel
}

enum BrowserAuthenticationMethod: Equatable, Sendable {
    case httpBasic
    case httpDigest
    case other
}

enum BrowserHTTPAuthenticationDecision: Sendable {
    case performDefaultHandling
    case cancel
    case useCredential(username: String, password: String)
}

struct BrowserHTTPAuthenticationDescriptor: Equatable, Sendable {
    let source: String
    let realm: String?
    let authenticationMethod: String
    let isSecureTransport: Bool
    let previousFailureCount: Int
}

struct BrowserHTTPAuthenticationPrompt: Equatable, Sendable {
    let descriptor: BrowserHTTPAuthenticationDescriptor
    let suggestedUsername: String?
    let allowsSaving: Bool
}

struct BrowserHTTPAuthenticationPromptResponse:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let username: String
    let password: String
    let shouldSave: Bool

    var description: String {
        "BrowserHTTPAuthenticationPromptResponse(username: \(username), password: <redacted>, shouldSave: \(shouldSave))"
    }

    var debugDescription: String { description }
}

struct BrowserHTTPAuthenticationProtectionSpace: Equatable, Hashable, Sendable {
    let origin: CredentialOrigin
    let credentialScope: BrowserCredentialScope

    init(origin: CredentialOrigin, credentialScope: BrowserCredentialScope) {
        precondition(credentialScope.isHTTPAuthentication)
        self.origin = origin
        self.credentialScope = credentialScope
    }
}

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
