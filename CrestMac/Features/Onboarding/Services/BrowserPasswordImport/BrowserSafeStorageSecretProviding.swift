protocol BrowserSafeStorageSecretProviding: Sendable {
    func secret(for application: BrowserImportApplication) throws -> String
}
