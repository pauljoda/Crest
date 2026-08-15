struct BrowserPasskeyPrivacyBoundary: Equatable, Sendable {
    let credentialAccess: BrowserPasskeyCredentialAccessScope
    let websiteSession: BrowserPasskeyWebsiteSessionScope
    let storesCredentialInventoryInCrest: Bool

    static let webKit = BrowserPasskeyPrivacyBoundary(
        credentialAccess: .applicationWideSystemProvider,
        websiteSession: .spaceIsolated,
        storesCredentialInventoryInCrest: false
    )
}
