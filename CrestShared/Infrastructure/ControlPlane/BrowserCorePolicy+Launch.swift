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
    /// The parsed launch flags, as the core's launch plan reads them.
    var coreEnvironment: LaunchEnvironment {
        LaunchEnvironment(
            isTestRuntime: isXCTestRuntime, isPreviewRuntime: isSwiftUIPreviewRuntime,
            requestsIsolatedSession: explicitlyRequiresIsolation, hasNamedProfile: persistentIsolationID != nil,
            requestsIsolatedCloudSync: requestsIsolatedCloudSync, resetsSession: resetsSession,
            presentsShowcase: presentsShowcaseSession, usesInMemoryCredentials: usesInMemoryCredentialVault,
            forcesOnboardingWelcome: forcesOnboardingWelcome, forcesDesktopSetup: forcesMacOnboardingSetup,
            forcesMobileSetup: forcesMobileOnboardingSetup, runsPerformanceHarness: performanceBaseURLString != nil,
            usesUpdateTestFeed: isolatedSoftwareUpdateFeedURL != nil)
    }

    /// The parsed launch flags, in the core's vocabulary. Raw values never cross.
    var coreFacts: BrowserCorePolicy.LaunchFacts {
        BrowserCorePolicy.LaunchFacts(
            testRuntime: isXCTestRuntime,
            previewRuntime: isSwiftUIPreviewRuntime,
            isolatedSession: explicitlyRequiresIsolation,
            namedProfile: persistentIsolationID != nil,
            isolatedCloudSync: requestsIsolatedCloudSync,
            resetSession: resetsSession,
            showcase: presentsShowcaseSession,
            inMemoryCredentials: usesInMemoryCredentialVault,
            onboardingWelcome: forcesOnboardingWelcome,
            desktopSetup: forcesMacOnboardingSetup,
            mobileSetup: forcesMobileOnboardingSetup,
            performanceHarness: performanceBaseURLString != nil,
            updateTestFeed: isolatedSoftwareUpdateFeedURL != nil)
    }
}

/// Launch isolation and the startup destination, owned by the portable core.
extension BrowserCorePolicy {
    // MARK: - Types

    /// The launch flags as the core's `launch.plan` environment names them.
    struct LaunchFacts: Encodable, Sendable {
        let testRuntime: Bool
        let previewRuntime: Bool
        let isolatedSession: Bool
        let namedProfile: Bool
        let isolatedCloudSync: Bool
        let resetSession: Bool
        let showcase: Bool
        let inMemoryCredentials: Bool
        let onboardingWelcome: Bool
        let desktopSetup: Bool
        let mobileSetup: Bool
        let performanceHarness: Bool
        let updateTestFeed: Bool
    }

    struct LaunchPlanRequest: Encodable, Sendable {
        let platform: DevicePlatform
        let environment: LaunchFacts
        let hasActiveLaunchGate: Bool
    }

    struct LaunchPlanAnswer: Decodable, Sendable {
        let requiresIsolation: Bool
        let usesEphemeralProfileStorage: Bool
        let presentsInstalledApplicationUI: Bool
        let startupBehavior: BrowserStartupBehavior
    }

    // MARK: - Static Variables

    static var devicePlatform: DevicePlatform {
        #if os(macOS)
            .desktop
        #else
            .mobile
        #endif
    }

    // MARK: - Actions - Launch

    /// Isolation, profile storage and installed-app presentation, decided
    /// before any session exists. Its startup answer is the one for a person
    /// who never chose; `BrowserStore.startupBehavior` reads the saved choice.
    static func launchPlan(for environment: BrowserLaunchEnvironment) -> BrowserLaunchPlan {
        plan(
            from: evaluate(
                .launchPlan, launchArguments(for: environment, hasActiveLaunchGate: false),
                answer: LaunchPlanAnswer.self))
    }

    static func plan(from answer: LaunchPlanAnswer?) -> BrowserLaunchPlan {
        guard let answer else { return .unavailable }
        return BrowserLaunchPlan(
            requiresIsolation: answer.requiresIsolation,
            usesEphemeralProfileStorage: answer.usesEphemeralProfileStorage,
            presentsInstalledApplicationUI: answer.presentsInstalledApplicationUI,
            startupBehavior: answer.startupBehavior)
    }

    private static func launchArguments(for environment: BrowserLaunchEnvironment, hasActiveLaunchGate: Bool)
        -> LaunchPlanRequest
    {
        LaunchPlanRequest(
            platform: devicePlatform, environment: environment.coreFacts, hasActiveLaunchGate: hasActiveLaunchGate)
    }
}

extension BrowserStore {
    /// The destination this launch's first window opens: the core's launch
    /// plan applies the saved startup preference this workspace keeps, the
    /// launch's isolation and any active setup; `hasActiveLaunchGate` is true
    /// while first-run setup owns the first window. A workspace that keeps no
    /// preferences opens the Start Page.
    func startupBehavior(for environment: BrowserLaunchEnvironment, hasActiveLaunchGate: Bool = false)
        -> BrowserStartupBehavior
    {
        let plan = LaunchPlan(
            workspaceID: family.workspaceID, platform: BrowserCorePolicy.devicePlatform,
            environment: environment.coreEnvironment, hasActiveLaunchGate: hasActiveLaunchGate)
        guard let decision = try? core.query(plan) else { return BrowserLaunchPlan.unavailable.startupBehavior }
        return BrowserStartupBehavior(coreTerm: decision.startup) ?? BrowserLaunchPlan.unavailable.startupBehavior
    }
}
