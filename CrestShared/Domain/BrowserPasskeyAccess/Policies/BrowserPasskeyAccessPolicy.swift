enum BrowserPasskeyAccessPolicy {
    static func status(
        hasManagedCapability: Bool,
        deviceConfiguration: BrowserPasskeyDeviceConfiguration,
        authorizationState: BrowserPasskeyAuthorizationState
    ) -> BrowserPasskeyAccessStatus {
        guard hasManagedCapability else {
            return .managedCapabilityRequired
        }
        guard deviceConfiguration != .notConfigured else {
            return .deviceNotConfigured
        }

        return switch authorizationState {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        }
    }
}
