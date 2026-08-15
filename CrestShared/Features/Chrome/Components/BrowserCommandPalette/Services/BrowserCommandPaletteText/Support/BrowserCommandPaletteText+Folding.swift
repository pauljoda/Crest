extension BrowserCommandPaletteText {
    private static let finalSigma: Unicode.Scalar = "ς"
    private static let sigma: Unicode.Scalar = "σ"

    static func folded(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar.isASCII {
            guard scalar.value >= 65, scalar.value <= 90 else { return scalar }
            return Unicode.Scalar(scalar.value + 32) ?? scalar
        }
        if scalar == finalSigma { return sigma }
        guard
            scalar.properties.isUppercase,
            let lowered = scalar.properties.lowercaseMapping.unicodeScalars.first
        else {
            return scalar
        }
        return lowered
    }

    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII
            ? scalar.value == 32 || scalar.value == 9
            : scalar.properties.isWhitespace
    }

    static func isBoundary(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            let value = scalar.value
            let isDigit = value >= 48 && value <= 57
            let isUppercase = value >= 65 && value <= 90
            let isLowercase = value >= 97 && value <= 122
            return !(isDigit || isUppercase || isLowercase)
        }
        return !(scalar.properties.isAlphabetic || scalar.properties.numericType != nil)
    }
}
