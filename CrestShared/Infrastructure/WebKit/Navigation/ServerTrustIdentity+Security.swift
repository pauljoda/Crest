import CryptoKit
import Foundation
import Security

extension BrowserServerTrustIdentity {
    static func challengeIdentity(
        for challenge: URLAuthenticationChallenge
    ) -> BrowserServerTrustIdentity? {
        let protectionSpace = challenge.protectionSpace
        guard
            protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
            let trust = protectionSpace.serverTrust,
            let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?
                .first
        else { return nil }

        let certificateData = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: certificateData)
            .map { String(format: "%02X", $0) }
            .joined()
        return BrowserServerTrustIdentity(
            host: protectionSpace.host,
            port: protectionSpace.port > 0 ? protectionSpace.port : 443,
            certificateSHA256: fingerprint
        )
    }
}
