enum BrowserExtensionNativeMessagingCapability:
    CaseIterable,
    Equatable,
    Sendable
{
    case available
    case unavailableInAppSandbox
    case unavailableOnPlatform
}
