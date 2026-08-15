import Foundation

extension BrowserNavigationFailure {
    var displayHost: String {
        failingURL?.host() ?? failingURL?.absoluteString ?? "this site"
    }

    var browserCode: String {
        switch kind {
        case .offline:
            "CREST_INTERNET_DISCONNECTED"
        case .timedOut:
            "CREST_TIMED_OUT"
        case .cannotFindServer:
            "CREST_NAME_NOT_RESOLVED"
        case .cannotConnect:
            "CREST_CONNECTION_REFUSED"
        case .connectionLost:
            "CREST_CONNECTION_RESET"
        case .secureConnectionFailed:
            "CREST_CERTIFICATE_INVALID"
        case .tooManyRedirects:
            "CREST_TOO_MANY_REDIRECTS"
        case .unsupportedAddress:
            "CREST_UNSUPPORTED_ADDRESS"
        case .blocked:
            "CREST_CONTENT_BLOCKED"
        case .unavailable:
            "CREST_RESOURCE_UNAVAILABLE"
        case .webContentProcessStopped:
            "CREST_WEB_PROCESS_STOPPED"
        case .unknown:
            "CREST_NAVIGATION_FAILED"
        }
    }
}
