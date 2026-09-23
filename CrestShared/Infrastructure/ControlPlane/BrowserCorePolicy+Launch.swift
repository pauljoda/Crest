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

    /// Isolation, profile storage and installed-app presentation, decided
    /// before any session exists. Its startup answer is the one for a person
    /// who never chose; `BrowserStore.startupBehavior` reads the saved choice.
    static func launchPlan(for environment: BrowserLaunchEnvironment) -> BrowserLaunchPlan {
        plan(from: evaluate(launchRequest(for: environment, hasActiveLaunchGate: false)))
    }

    /// `hasActiveLaunchGate` is true while first-run setup owns the first window.
    static func launchRequest(for environment: BrowserLaunchEnvironment, hasActiveLaunchGate: Bool) -> [String: Any] {
        [
            "version": 1, "operation": "launch.plan", "platform": devicePlatform,
            "environment": environment.coreFacts, "hasActiveLaunchGate": hasActiveLaunchGate,
        ]
    }

    static func plan(from response: [String: Any]?) -> BrowserLaunchPlan {
        guard let response, let isolated = response["requiresIsolation"] as? Bool,
            let ephemeral = response["usesEphemeralProfileStorage"] as? Bool,
            let presents = response["presentsInstalledApplicationUI"] as? Bool,
            let startup = (response["startupBehavior"] as? String).flatMap(BrowserStartupBehavior.init(rawValue:))
        else { return .unavailable }
        return BrowserLaunchPlan(requiresIsolation: isolated, usesEphemeralProfileStorage: ephemeral,
            presentsInstalledApplicationUI: presents, startupBehavior: startup)
    }
}

extension BrowserStore {
    /// The destination this launch's first window opens: the session's
    /// `launch.plan` applies the saved startup preference the core owns, the
    /// launch's isolation and any active setup. Without an answer the window
    /// opens the Start Page.
    func startupBehavior(for environment: BrowserLaunchEnvironment, hasActiveLaunchGate: Bool = false)
        -> BrowserStartupBehavior {
        let request = BrowserCorePolicy.launchRequest(for: environment, hasActiveLaunchGate: hasActiveLaunchGate)
        let response = family.readCore(request).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        return BrowserCorePolicy.plan(from: response).startupBehavior
    }
}
