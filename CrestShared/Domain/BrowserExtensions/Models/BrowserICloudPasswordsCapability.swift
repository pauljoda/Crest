enum BrowserICloudPasswordsCapability: Equatable, Sendable {
    case available
    case missingManagedBrowserCredentialEntitlement
    case unavailableOnPlatform
}
