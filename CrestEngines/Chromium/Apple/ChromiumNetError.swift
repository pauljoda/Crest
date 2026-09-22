#if CREST_CHROMIUM_HOST
import Foundation

extension BrowserNavigationFailure {
    /// A navigation the engine replaced with its error page, described by
    /// Chromium's `net::Error` code (`net/base/net_error_list.h`).
    init(chromiumNetError code: Int, failingURL: URL?) {
        self.init(
            kind: Self.kind(forChromiumNetError: code),
            phase: .provisional,
            failingURL: failingURL,
            errorDomain: "net",
            errorCode: code
        )
    }

    private static func kind(forChromiumNetError code: Int) -> BrowserNavigationFailureKind {
        switch code {
        case -106: .offline
        case -7, -118: .timedOut
        case -105, -137: .cannotFindServer
        case -102, -104, -109: .cannotConnect
        case -100, -101, -103, -21: .connectionLost
        case -107, -113, -299 ... -200: .secureConnectionFailed
        case -310: .tooManyRedirects
        case -300, -301, -302: .unsupportedAddress
        case -20, -22, -27: .blocked
        default: .unknown
        }
    }
}
#endif
