#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageFailure {
        /// A navigation the engine replaced with its error page, described by
        /// Chromium's `net::Error` code (`net/base/net_error_list.h`). The error
        /// page is a committed document, so it replaced the one the page showed.
        init(chromiumNetError code: Int, failingURL: URL?) {
            self.init(
                error: Self.kind(forChromiumNetError: code),
                url: failingURL?.absoluteString,
                replacedDocument: true,
                domain: "net",
                code: Int64(code)
            )
        }

        private static func kind(forChromiumNetError code: Int) -> NavigationError {
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
