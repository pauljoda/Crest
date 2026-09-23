/// What a page's notification permission request leads to. The core decides
/// it from the saved choice and the request's user activation.
enum BrowserHostedWebNotificationPermissionRequestAction: String, Decodable, Equatable, Sendable {
    case respondDefault
    case respondDenied
    case resolveSystemAuthorization
    case promptForSitePermission
}
