import Foundation

/// This launch's platform facts for the core's Apple Passwords rule. The core
/// decides from them; app code asks `core.query(availability(...))` and never
/// builds an `ApplePasswordsSupport` itself.
@MainActor
enum BrowserApplePasswordsSystem {
    /// Apple's iCloud Passwords extension in the Chrome Web Store: the extension
    /// whose presence in a Space the rule weighs against the helper.
    static let appleExtensionID = "pejdijmoenmkgeppbflobdenhhabjlaj"

    /// The question the core answers for one Space.
    /// - Parameters:
    ///   - helper: The shared helper's state, mapped once here to the core's fact.
    ///   - applePasswordsExtensionEnabled: Whether `appleExtensionID` is installed
    ///     and enabled in the Space. Only the Chromium engine knows; its extension
    ///     store answers (`ChromiumExtensionStore.isApplePasswordsExtensionEnabled`),
    ///     and the caller passes the answer in, false when that engine is absent.
    static func availability(
        helper: ApplePasswordsHelper.State,
        preferences: CredentialPreferences,
        isPrivateBrowsing: Bool,
        applePasswordsExtensionEnabled: Bool,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> ApplePasswordsAvailability {
        ApplePasswordsAvailability(
            isMacPlatform: true,
            hasManagedBrowserCapability: BrowserPasskeyAccessSystem.hasManagedCapability(),
            isLaunchIsolated: launchEnvironment.requiresIsolation,
            isPrivateBrowsing: isPrivateBrowsing,
            spaceCredentialsEnabled: preferences.isEnabled,
            spaceUsesApplePasswords: preferences.usesApplePasswords,
            applePasswordsExtensionEnabled: applePasswordsExtensionEnabled,
            helper: fact(for: helper)
        )
    }

    /// The helper's state as the core's fact: the one place they meet. An
    /// unavailable helper reads as not started: the person can ask to pair
    /// again, which starts it afresh, and the core still refuses an isolated
    /// launch or a private window first.
    static func fact(for state: ApplePasswordsHelper.State) -> ApplePasswordsHelperFact {
        switch state {
        case .stopped, .unavailable: return .notStarted
        case .unpaired, .awaitingCode: return .unpaired
        case .paired: return .paired
        }
    }
}
