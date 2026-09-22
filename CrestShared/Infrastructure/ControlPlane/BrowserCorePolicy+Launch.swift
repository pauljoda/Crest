import Foundation

/// How one launch treats the person's data and what its first window opens.
struct BrowserLaunchPlan: Equatable, Sendable {
    let requiresIsolation: Bool
    let usesEphemeralProfileStorage: Bool
    let presentsInstalledApplicationUI: Bool
    let startupBehavior: BrowserStartupBehavior

    /// What a launch does when the core cannot answer: stay out of the
    /// installed profile and forget everything, and open the documented
    /// default destination.
    static let unavailable = BrowserLaunchPlan(
        requiresIsolation: true,
        usesEphemeralProfileStorage: true,
        presentsInstalledApplicationUI: false,
        startupBehavior: .defaultBehavior
    )
}

extension BrowserLaunchEnvironment {
    /// The parsed launch flags, in the core's vocabulary. Raw values never cross.
    var coreFacts: [String: Any] {
        [
            "testRuntime": isXCTestRuntime,
            "previewRuntime": isSwiftUIPreviewRuntime,
            "isolatedSession": explicitlyRequiresIsolation,
            "namedProfile": persistentIsolationID != nil,
            "isolatedCloudSync": requestsIsolatedCloudSync,
            "resetSession": resetsSession,
            "showcase": presentsShowcaseSession,
            "inMemoryCredentials": usesInMemoryCredentialVault,
            "onboardingWelcome": forcesOnboardingWelcome,
            "desktopSetup": forcesMacOnboardingSetup,
            "mobileSetup": forcesMobileOnboardingSetup,
            "performanceHarness": performanceBaseURLString != nil,
            "updateTestFeed": isolatedSoftwareUpdateFeedURL != nil,
        ]
    }
}

/// Launch isolation and the startup destination, owned by the portable core.
extension BrowserCorePolicy {
    static var devicePlatform: String {
        #if os(macOS)
            "desktop"
        #else
            "mobile"
        #endif
    }

    /// `storedStartupBehavior` is the saved preference's raw value.
    /// `hasActiveLaunchGate` is true while first-run setup owns the first window.
    static func launchPlan(for environment: BrowserLaunchEnvironment, storedStartupBehavior: String? = nil,
        hasActiveLaunchGate: Bool = false) -> BrowserLaunchPlan {
        guard let response = evaluate([
            "version": 1, "operation": "launch.plan", "platform": devicePlatform,
            "environment": environment.coreFacts,
            "storedStartupBehavior": storedStartupBehavior as Any? ?? NSNull(),
            "hasActiveLaunchGate": hasActiveLaunchGate,
        ]), let isolated = response["requiresIsolation"] as? Bool,
            let ephemeral = response["usesEphemeralProfileStorage"] as? Bool,
            let presents = response["presentsInstalledApplicationUI"] as? Bool,
            let startup = (response["startupBehavior"] as? String).flatMap(BrowserStartupBehavior.init(rawValue:))
        else { return .unavailable }
        return BrowserLaunchPlan(requiresIsolation: isolated, usesEphemeralProfileStorage: ephemeral,
            presentsInstalledApplicationUI: presents, startupBehavior: startup)
    }

    /// The destination a launch's first window opens, from the saved choice in
    /// `defaults`, the launch's isolation and any active setup. An isolated
    /// launch never reads the installed profile's choice.
    static func startupBehavior(for environment: BrowserLaunchEnvironment, hasActiveLaunchGate: Bool = false,
        defaults: UserDefaults = .standard) -> BrowserStartupBehavior {
        let stored = environment.requiresIsolation ? nil : defaults.string(forKey: BrowserStartupPreference.key)
        return launchPlan(for: environment, storedStartupBehavior: stored,
            hasActiveLaunchGate: hasActiveLaunchGate).startupBehavior
    }
}
