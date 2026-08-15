import Foundation
import Security

@MainActor
enum BrowserPasskeyAccessSystem {
    private static let managedEntitlement =
        "com.apple.developer.web-browser.public-key-credential"

    static func hasManagedCapability() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  managedEntitlement as CFString,
                  nil
              ) else {
            return false
        }
        return value as? Bool == true
    }

    static func deviceConfiguration() -> BrowserPasskeyDeviceConfiguration {
        BrowserPasskeyAuthorizationSystem.deviceConfiguration()
    }

    static func authorizationState() -> BrowserPasskeyAuthorizationState {
        BrowserPasskeyAuthorizationSystem.authorizationState()
    }

    static func requestAuthorization() async -> BrowserPasskeyAuthorizationState {
        await BrowserPasskeyAuthorizationSystem.requestAuthorization()
    }
}
