import Foundation
import Security

enum BrowserPlatformCloudContainerEntitlementPolicy {
    static func currentProcessContainsContainer(
        _ containerIdentifier: String
    ) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task,
            BrowserCloudContainerEntitlementPolicy.entitlementName as CFString,
            nil
        )
        return BrowserCloudContainerEntitlementPolicy.containsContainer(
            containerIdentifier,
            entitlementValue: value
        )
    }
}
