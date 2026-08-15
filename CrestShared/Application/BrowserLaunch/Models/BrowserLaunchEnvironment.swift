struct BrowserLaunchEnvironment: Equatable, Sendable {
    let explicitlyRequiresIsolation: Bool
    let resetsSession: Bool
    let presentsShowcaseSession: Bool
    let usesInMemoryCredentialVault: Bool
    let forcesOnboardingWelcome: Bool
    let forcesMacOnboardingSetup: Bool
    let forcesMobileOnboardingSetup: Bool
    let performanceBaseURLString: String?
    let performanceTabCount: String?
    let performanceRunID: String
    let isXCTestRuntime: Bool
    let isSwiftUIPreviewRuntime: Bool

    init(
        values: [String: String],
        isXCTestRuntime: Bool,
        isSwiftUIPreviewRuntime: Bool = false
    ) {
        explicitlyRequiresIsolation = Self.isEnabled(.isolatedSession, in: values)
        resetsSession = Self.isEnabled(.resetSession, in: values)
        presentsShowcaseSession = Self.isEnabled(.showcaseSession, in: values)
        usesInMemoryCredentialVault = Self.isEnabled(
            .useInMemoryCredentials,
            in: values
        )
        forcesOnboardingWelcome = Self.isEnabled(.showOnboarding, in: values)
        forcesMacOnboardingSetup = Self.isEnabled(.showSetup, in: values)
        forcesMobileOnboardingSetup = Self.isEnabled(
            .forceOnboardingSetup,
            in: values
        )
        performanceBaseURLString = values[Key.performanceBaseURL.rawValue]
        performanceTabCount = values[Key.performanceTabCount.rawValue]
        performanceRunID =
            values[Key.performanceRunID.rawValue]
            ?? Defaults.performanceRunID
        self.isXCTestRuntime = isXCTestRuntime
        self.isSwiftUIPreviewRuntime = isSwiftUIPreviewRuntime
    }

    private static func isEnabled(
        _ key: Key,
        in values: [String: String]
    ) -> Bool {
        values[key.rawValue] == "1"
    }

    private enum Key: String {
        case isolatedSession = "CREST_ISOLATED_SESSION"
        case resetSession = "CREST_RESET_SESSION"
        case showcaseSession = "CREST_SHOWCASE_SESSION"
        case useInMemoryCredentials = "CREST_USE_IN_MEMORY_CREDENTIALS"
        case showOnboarding = "CREST_SHOW_ONBOARDING"
        case showSetup = "CREST_SHOW_SETUP"
        case forceOnboardingSetup = "CREST_FORCE_ONBOARDING_SETUP"
        case performanceBaseURL = "CREST_PERFORMANCE_BASE_URL"
        case performanceTabCount = "CREST_PERFORMANCE_TAB_COUNT"
        case performanceRunID = "CREST_PERFORMANCE_RUN_ID"
    }

    private enum Defaults {
        static let performanceRunID = "release-soak"
    }
}
