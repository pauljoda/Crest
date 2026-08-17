struct BrowserExtensionCompatibilityAssessment: Equatable, Sendable {
    let issues: [BrowserExtensionCompatibilityIssue]

    var blockingIssues: [BrowserExtensionCompatibilityIssue] {
        issues.filter(\.isBlocking)
    }

    var canRun: Bool {
        blockingIssues.isEmpty
    }

    static let compatible = BrowserExtensionCompatibilityAssessment(
        issues: []
    )
}

struct BrowserExtensionCompatibilityError: Error, Equatable {
    let assessment: BrowserExtensionCompatibilityAssessment
}

struct BrowserExtensionCompatibilityIssue: Equatable, Sendable {
    let kind: BrowserExtensionCompatibilityIssueKind
    let isBlocking: Bool
}

enum BrowserExtensionCompatibilityIssueKind:
    CaseIterable,
    Equatable,
    Sendable
{
    case nativeMessagingUnavailable
    case unverifiedNativeMessaging
    case foreignSafariNativeHandler
    case knownRuntimeLimitation
}

enum BrowserExtensionCompatibilitySource: Equatable, Sendable {
    case unpackedPackage
    case chromeWebStore
    case mozillaAddons
    case safariAppExtensionBundle
}

enum BrowserExtensionNativeMessagingCapability:
    CaseIterable,
    Equatable,
    Sendable
{
    case available
    case unavailableInAppSandbox
    case unavailableOnPlatform
}

enum BrowserICloudPasswordsCapability: Equatable, Sendable {
    case available
    case missingManagedBrowserCredentialEntitlement
    case unavailableOnPlatform
}
