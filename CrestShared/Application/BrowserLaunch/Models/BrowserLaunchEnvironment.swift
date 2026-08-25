struct BrowserLaunchEnvironment: Equatable, Sendable {
    let explicitlyRequiresIsolation: Bool
    let persistentIsolationID: String?
    let resetsSession: Bool
    let presentsShowcaseSession: Bool
    let usesInMemoryCredentialVault: Bool
    let forcesOnboardingWelcome: Bool
    let forcesMacOnboardingSetup: Bool
    let forcesMobileOnboardingSetup: Bool
    let performanceBaseURLString: String?
    let performanceTabCount: String?
    let performanceRunID: String
    let softwareUpdateWidgetFixture: String?
    let isXCTestRuntime: Bool
    let isSwiftUIPreviewRuntime: Bool

    init(
        values: [String: String],
        isXCTestRuntime: Bool,
        isSwiftUIPreviewRuntime: Bool = false
    ) {
        explicitlyRequiresIsolation = Self.isEnabled(.isolatedSession, in: values)
        persistentIsolationID = values[Key.persistentIsolationID.rawValue]
            .flatMap(Self.normalizedIsolationID)
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
        softwareUpdateWidgetFixture =
            values[
                Key.softwareUpdateWidgetFixture.rawValue
            ]
        self.isXCTestRuntime = isXCTestRuntime
        self.isSwiftUIPreviewRuntime = isSwiftUIPreviewRuntime
    }

    private static func isEnabled(
        _ key: Key,
        in values: [String: String]
    ) -> Bool {
        values[key.rawValue] == "1"
    }

    private static func normalizedIsolationID(_ rawValue: String) -> String? {
        let normalized = rawValue.lowercased().filter {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
        }
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(48))
    }

    private enum Key: String {
        case isolatedSession = "CREST_ISOLATED_SESSION"
        case persistentIsolationID = "CREST_ISOLATED_PERSISTENCE_ID"
        case resetSession = "CREST_RESET_SESSION"
        case showcaseSession = "CREST_SHOWCASE_SESSION"
        case useInMemoryCredentials = "CREST_USE_IN_MEMORY_CREDENTIALS"
        case showOnboarding = "CREST_SHOW_ONBOARDING"
        case showSetup = "CREST_SHOW_SETUP"
        case forceOnboardingSetup = "CREST_FORCE_ONBOARDING_SETUP"
        case performanceBaseURL = "CREST_PERFORMANCE_BASE_URL"
        case performanceTabCount = "CREST_PERFORMANCE_TAB_COUNT"
        case performanceRunID = "CREST_PERFORMANCE_RUN_ID"
        case softwareUpdateWidgetFixture = "CREST_UPDATE_WIDGET_FIXTURE"
    }

    private enum Defaults {
        static let performanceRunID = "release-soak"
    }
}
