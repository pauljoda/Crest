import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

#if CREST_PHYSICAL_VALIDATION
    import CryptoKit
    import OSLog
    import Security
#endif

#if CREST_PHYSICAL_VALIDATION
    enum MobilePhysicalValidationServerTrust {
        private static let logger = Logger(
            subsystem: "com.pauldavis.crest.physical-validation",
            category: "FixtureTrust"
        )

        static func credential(for challenge: URLAuthenticationChallenge) -> URLCredential? {
            guard
                challenge.protectionSpace.authenticationMethod
                    == NSURLAuthenticationMethodServerTrust,
                let trust = challenge.protectionSpace.serverTrust,
                let leafCertificate = SecTrustGetCertificateAtIndex(trust, 0)
            else {
                return nil
            }
            let certificateData = SecCertificateCopyData(leafCertificate) as Data
            let fingerprint = SHA256.hash(data: certificateData)
                .map { String(format: "%02x", $0) }
                .joined()
            let expectedFingerprint = ProcessInfo.processInfo.environment[
                "CREST_PHYSICAL_FIXTURE_CERT_SHA256"
            ]
            let bundleMatches =
                Bundle.main.bundleIdentifier
                == BrowserPhysicalValidationTrustPolicy.bundleIdentifier
            let fingerprintMatches =
                expectedFingerprint?.caseInsensitiveCompare(fingerprint)
                == .orderedSame
            let isAllowed = BrowserPhysicalValidationTrustPolicy.allows(
                bundleIdentifier: Bundle.main.bundleIdentifier,
                expectedCertificateSHA256: expectedFingerprint,
                actualCertificateSHA256: fingerprint
            )
            logger.notice(
                "Physical fixture server trust evaluated: host=\(challenge.protectionSpace.host, privacy: .public), allowed=\(isAllowed, privacy: .public), bundleMatches=\(bundleMatches, privacy: .public), fingerprintMatches=\(fingerprintMatches, privacy: .public)"
            )
            guard isAllowed else {
                return nil
            }
            return URLCredential(trust: trust)
        }
    }
#endif
