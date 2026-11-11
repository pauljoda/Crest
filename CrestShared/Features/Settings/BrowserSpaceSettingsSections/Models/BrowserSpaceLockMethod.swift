import Foundation
import LocalAuthentication

/// How this device asks its owner before a locked Space shows: the biometry it
/// has, with the passcode or password behind it, named as the system names it.
struct BrowserSpaceLockMethod: Sendable {
    // MARK: - Static Variables

    static let faceID = BrowserSpaceLockMethod(toggleTitle: "Require Face ID or passcode")
    static let opticID = BrowserSpaceLockMethod(toggleTitle: "Require Optic ID or passcode")
    #if os(macOS)
        static let touchID = BrowserSpaceLockMethod(toggleTitle: "Require Touch ID or password")
        static let passcode = BrowserSpaceLockMethod(toggleTitle: "Require password")
    #else
        static let touchID = BrowserSpaceLockMethod(toggleTitle: "Require Touch ID or passcode")
        static let passcode = BrowserSpaceLockMethod(toggleTitle: "Require passcode")
    #endif

    /// The method this device's hardware offers. The system names the biometry
    /// once asked whether it can authenticate, whatever the answer, so a device
    /// with no face or finger enrolled still reads as the one it is.
    static let current: BrowserSpaceLockMethod = {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }()

    // MARK: - Variables

    /// What the lock's toggle says.
    let toggleTitle: LocalizedStringResource
}
