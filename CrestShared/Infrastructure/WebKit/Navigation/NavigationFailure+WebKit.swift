import Foundation
import WebKit

extension BrowserNavigationFailure {
    init?(
        error: any Error,
        phase: BrowserNavigationFailurePhase,
        fallbackURL: URL?
    ) {
        let error = error as NSError
        guard !Self.isExpectedInterruption(error) else { return nil }

        self.init(
            kind: Self.kind(for: error),
            phase: phase,
            failingURL: Self.failingURL(in: error) ?? fallbackURL,
            errorDomain: error.domain,
            errorCode: error.code
        )
    }

    static func webContentProcessStopped(url: URL?) -> BrowserNavigationFailure {
        BrowserNavigationFailure(
            kind: .webContentProcessStopped,
            phase: .committed,
            failingURL: url,
            errorDomain: WKError.errorDomain,
            errorCode: WKError.webContentProcessTerminated.rawValue
        )
    }

    private static func isExpectedInterruption(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: error.code)
            return code == .cancelled || code == .userCancelledAuthentication
        }
        if error.domain == WKError.errorDomain,
            error.code == WKError.webContentProcessTerminated.rawValue
        {
            return true
        }
        // WebKit reports this legacy error when a response intentionally changes
        // policy: most commonly when a navigation becomes a download, and also
        // when Crest cancels a navigation to hand its URL to another app. Neither
        // is a failure the user should see an error page for.
        return error.domain == "WebKitErrorDomain" && error.code == 102
    }

    private static func kind(for error: NSError) -> BrowserNavigationFailureKind {
        guard error.domain == NSURLErrorDomain else {
            if error.domain == WKError.errorDomain {
                return .unavailable
            }
            return .unknown
        }

        switch URLError.Code(rawValue: error.code) {
        case .notConnectedToInternet,
            .internationalRoamingOff,
            .dataNotAllowed,
            .callIsActive:
            return .offline
        case .timedOut:
            return .timedOut
        case .cannotFindHost,
            .dnsLookupFailed:
            return .cannotFindServer
        case .cannotConnectToHost:
            return .cannotConnect
        case .networkConnectionLost:
            return .connectionLost
        case .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired:
            return .secureConnectionFailed
        case .httpTooManyRedirects,
            .redirectToNonExistentLocation:
            return .tooManyRedirects
        case .badURL,
            .unsupportedURL:
            return .unsupportedAddress
        case .appTransportSecurityRequiresSecureConnection,
            .noPermissionsToReadFile:
            return .blocked
        case .badServerResponse,
            .cannotDecodeContentData,
            .cannotDecodeRawData,
            .cannotParseResponse,
            .resourceUnavailable,
            .zeroByteResource:
            return .unavailable
        default:
            return .unknown
        }
    }

    private static func failingURL(in error: NSError) -> URL? {
        error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }
}
