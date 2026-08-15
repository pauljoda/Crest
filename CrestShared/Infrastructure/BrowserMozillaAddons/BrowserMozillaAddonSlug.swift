import Foundation

/// The URL-safe name an add-on is published under on addons.mozilla.org.
///
/// The slug reaches a URL path segment, an API path segment, and a staged
/// package name, so it is constrained to the characters AMO itself allows
/// rather than trusted as free text from a page.
struct BrowserMozillaAddonSlug:
    Codable,
    Equatable,
    Hashable,
    RawRepresentable,
    Sendable
{
    static let maximumLength = 100

    let rawValue: String

    init?(_ rawValue: String) {
        guard !rawValue.isEmpty,
            rawValue.utf8.count <= Self.maximumLength,
            rawValue.utf8.allSatisfy(Self.isSlugByte)
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    init?(rawValue: String) {
        self.init(rawValue)
    }

    private static func isSlugByte(_ byte: UInt8) -> Bool {
        (0x61...0x7a).contains(byte)
            || (0x41...0x5a).contains(byte)
            || (0x30...0x39).contains(byte)
            || byte == 0x2d
            || byte == 0x5f
    }
}
