import Foundation
import Security

extension BrowserICloudPasswordsCapability {
    static var currentBuild: Self {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return .missingManagedBrowserCredentialEntitlement
        }
        let entitlement = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.web-browser.public-key-credential" as CFString,
            nil
        )
        return macOS(
            hasManagedBrowserCredentialEntitlement:
                entitlement as? Bool == true
        )
    }

    static func macOS(
        hasManagedBrowserCredentialEntitlement: Bool
    ) -> Self {
        hasManagedBrowserCredentialEntitlement
            ? .available
            : .missingManagedBrowserCredentialEntitlement
    }
}
