import Foundation

extension BrowserAuthenticationMethod {
    init(authenticationMethod: String) {
        switch authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic:
            self = .httpBasic
        case NSURLAuthenticationMethodHTTPDigest:
            self = .httpDigest
        default:
            self = .other
        }
    }
}
