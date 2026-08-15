enum BrowserExtensionCompatibilityIssueKind:
    CaseIterable,
    Equatable,
    Sendable
{
    case nativeMessagingUnavailable
    case unverifiedNativeMessaging
    case unsupportedMozillaNativeMessaging
    case foreignSafariNativeHandler
    case knownRuntimeLimitation
}
