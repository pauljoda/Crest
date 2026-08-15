import Foundation
import Security

enum BrowserPlatformExtensionNativeMessagingCapability {
    static var currentBuild: BrowserExtensionNativeMessagingCapability {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return .unavailableInAppSandbox
        }
        let entitlement = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.app-sandbox" as CFString,
            nil
        )
        return macOS(appSandboxEnabled: entitlement as? Bool == true)
    }

    static func macOS(
        appSandboxEnabled: Bool
    ) -> BrowserExtensionNativeMessagingCapability {
        appSandboxEnabled ? .unavailableInAppSandbox : .available
    }
}
