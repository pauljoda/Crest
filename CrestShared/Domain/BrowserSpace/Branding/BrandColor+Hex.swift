import Foundation

/// A color as a hex code, the way people copy colors between apps.
extension BrandColor {
    // MARK: - Variables

    /// The color as a number sign and six uppercase hexadecimal digits, such
    /// as #1D2340, leaving out its opacity.
    var hexCode: String {
        let digits = [red, green, blue].map { component in
            String(format: "%02X", Int((Swift.min(Swift.max(component, 0), 1) * 255).rounded()))
        }
        return "#" + digits.joined()
    }

    // MARK: - Initializers

    /// The opaque color `text` spells as a hex code: six digits, or three
    /// that each stand for a pair, with or without a number sign and in either
    /// case; nil for anything else.
    init?(hexCode text: String) {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
            return nil
        }
        self.init(
            red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
