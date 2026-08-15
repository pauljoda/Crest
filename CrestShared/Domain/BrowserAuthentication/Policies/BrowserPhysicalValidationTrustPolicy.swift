struct BrowserPhysicalValidationTrustPolicy {
    static let bundleIdentifier = "com.pauldavis.crest.physical-validation"

    static func allows(
        bundleIdentifier: String?,
        expectedCertificateSHA256: String?,
        actualCertificateSHA256: String
    ) -> Bool {
        guard bundleIdentifier == self.bundleIdentifier,
            let expectedCertificateSHA256,
            isSHA256(expectedCertificateSHA256),
            isSHA256(actualCertificateSHA256)
        else {
            return false
        }
        return expectedCertificateSHA256.lowercased()
            == actualCertificateSHA256.lowercased()
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 48...57, 65...70, 97...102:
                    return true
                default:
                    return false
                }
            }
    }
}
