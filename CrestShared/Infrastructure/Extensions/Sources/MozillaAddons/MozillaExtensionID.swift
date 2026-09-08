import Foundation

/// A Firefox add-on's gecko identity, as published in the add-on's
/// `browser_specific_settings.gecko.id` and in the AMO API's `guid` field.
///
/// Mozilla accepts exactly two shapes: a braced UUID, or an email-like
/// identifier. Nothing else is a valid gecko ID, so anything else is rejected
/// here rather than downstream where the value would already have reached a
/// file name, a registry record, or a runtime identifier.
struct BrowserMozillaExtensionID:
    Codable,
    Equatable,
    Hashable,
    RawRepresentable,
    Sendable
{
    /// Mozilla's own published ceiling for a gecko ID.
    static let maximumLength = 255

    let rawValue: String

    init?(_ rawValue: String) {
        guard !rawValue.isEmpty,
            rawValue.utf8.count <= Self.maximumLength,
            Self.isBracedUUID(rawValue) || Self.isEmailShaped(rawValue)
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    init?(rawValue: String) {
        self.init(rawValue)
    }

    /// The identity reduced to characters that are unremarkable in a file name.
    ///
    /// Both gecko shapes carry punctuation — `@` in the email shape, braces in
    /// the UUID shape — that has no business reaching a staged package name
    /// even though the path guard would tolerate it.
    var packageNameComponent: String {
        String(
            rawValue.map { character in
                character.isLetter || character.isNumber
                    || character == "." || character == "-"
                    || character == "_"
                    ? character
                    : "-"
            }
        )
    }

    private static func isBracedUUID(_ value: String) -> Bool {
        guard value.hasPrefix("{"), value.hasSuffix("}") else { return false }
        return UUID(uuidString: String(value.dropFirst().dropLast())) != nil
    }

    private static func isEmailShaped(_ value: String) -> Bool {
        let parts = value.split(
            separator: "@",
            omittingEmptySubsequences: false
        )
        guard parts.count == 2, !parts[1].isEmpty else { return false }
        return parts.allSatisfy { part in
            part.utf8.allSatisfy(isIdentifierByte)
        }
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (0x61...0x7a).contains(byte)
            || (0x41...0x5a).contains(byte)
            || (0x30...0x39).contains(byte)
            || byte == 0x2d
            || byte == 0x2e
            || byte == 0x5f
    }
}
