import Foundation

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
    let performanceHeavySession: Bool
    let performanceRunID: String
    let softwareUpdateWidgetFixture: String?
    let isolatedSoftwareUpdateFeedURL: URL?
    /// Whether extension pages forward their own console output to Crest's
    /// diagnostics channel. Verbose by design, so it is opt-in per launch.
    let capturesExtensionConsole: Bool
    /// Whether an isolated launch may reach the native messaging hosts that
    /// Chrome and Firefox extensions install on this Mac. Off by default so a
    /// validation launch never runs a companion process by accident; on only
    /// when a run needs the real companion.
    let allowsExternalNativeHostsInIsolation: Bool
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
        performanceHeavySession = Self.isEnabled(
            .performanceHeavySession,
            in: values
        )
        performanceRunID =
            values[Key.performanceRunID.rawValue]
            ?? Defaults.performanceRunID
        softwareUpdateWidgetFixture =
            values[
                Key.softwareUpdateWidgetFixture.rawValue
            ]
        isolatedSoftwareUpdateFeedURL = Self.loopbackSoftwareUpdateFeedURL(
            values[Key.softwareUpdateTestFeedURL.rawValue]
        )
        capturesExtensionConsole = Self.isEnabled(
            .extensionConsoleCapture,
            in: values
        )
        allowsExternalNativeHostsInIsolation = Self.isEnabled(
            .isolatedExternalNativeHosts,
            in: values
        )
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

    private static func loopbackSoftwareUpdateFeedURL(_ value: String?) -> URL? {
        guard let value, var components = URLComponents(string: value) else {
            return nil
        }
        let loopbackHosts = ["127.0.0.1", "localhost", "::1"]
        guard
            components.scheme?.lowercased() == "http",
            components.user == nil,
            components.password == nil,
            let host = components.host?.lowercased(),
            loopbackHosts.contains(host),
            !components.path.isEmpty
        else { return nil }
        components.fragment = nil
        return components.url
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
        case performanceHeavySession = "CREST_PERFORMANCE_HEAVY_SESSION"
        case performanceRunID = "CREST_PERFORMANCE_RUN_ID"
        case softwareUpdateWidgetFixture = "CREST_UPDATE_WIDGET_FIXTURE"
        case softwareUpdateTestFeedURL = "CREST_UPDATE_TEST_FEED_URL"
        case extensionConsoleCapture = "CREST_EXTENSION_CONSOLE_CAPTURE"
        case isolatedExternalNativeHosts = "CREST_ISOLATED_EXTERNAL_NATIVE_HOSTS"
    }

    private enum Defaults {
        static let performanceRunID = "release-soak"
    }
}
