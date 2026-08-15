struct BrowserPasswordImportCandidate: Sendable {
    let sourceApplication: BrowserImportApplication
    let sourceProfileID: String
    let sourceProfileName: String
    let origin: CredentialOrigin
}
