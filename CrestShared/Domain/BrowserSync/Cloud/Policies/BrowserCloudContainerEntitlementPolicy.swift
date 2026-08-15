enum BrowserCloudContainerEntitlementPolicy {
    static let entitlementName = "com.apple.developer.icloud-container-identifiers"

    static func containsContainer(
        _ containerIdentifier: String,
        entitlementValue: Any?
    ) -> Bool {
        guard let identifiers = entitlementValue as? [String] else { return false }
        return identifiers.contains(containerIdentifier)
    }
}
