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
