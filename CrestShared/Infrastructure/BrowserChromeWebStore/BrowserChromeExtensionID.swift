import Foundation

struct BrowserChromeExtensionID:
    Codable,
    Equatable,
    Hashable,
    RawRepresentable,
    Sendable
{
    let rawValue: String

    init?(_ rawValue: String) {
        guard rawValue.utf8.count == 32,
            rawValue.utf8.allSatisfy({ (0x61...0x70).contains($0) })
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    init?(rawValue: String) {
        self.init(rawValue)
    }
}
