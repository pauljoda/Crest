enum BrowserPlatformCloudContainerEntitlementPolicy {
    static func currentProcessContainsContainer(
        _ containerIdentifier: String
    ) -> Bool {
        // iOS validates the configured CloudKit container through the signed
        // application configuration when the container is opened.
        true
    }
}
