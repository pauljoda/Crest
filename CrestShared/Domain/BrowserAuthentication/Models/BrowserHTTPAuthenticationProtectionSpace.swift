struct BrowserHTTPAuthenticationProtectionSpace: Equatable, Hashable, Sendable {
    let origin: CredentialOrigin
    let credentialScope: BrowserCredentialScope

    init(origin: CredentialOrigin, credentialScope: BrowserCredentialScope) {
        precondition(credentialScope.isHTTPAuthentication)
        self.origin = origin
        self.credentialScope = credentialScope
    }
}
