extension KeychainCredentialVault {
    /// The vault over the Keychain, which asks `core` which saved passwords
    /// fill a page.
    init(
        core: CrestCore,
        servicePrefix: String = CredentialKeychainNamespace.productionPrefix
    ) {
        self.init(
            store: SecurityCredentialKeychainStore(),
            servicePrefix: servicePrefix,
            fills: { page, saved in try core.fills(page, from: saved) }
        )
    }
}
