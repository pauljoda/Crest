import Foundation
import Security

/// Whether this build may launch an **external** native host process.
///
/// App Sandbox forbids spawning the vendor's companion executable, so a
/// sandboxed build reports `.unavailableInAppSandbox`. This says nothing about
/// Crest's own in-process capability broker, which spawns no process and stays
/// available everywhere; see `BrowserExtensionNativeMessagingHandling`.
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
