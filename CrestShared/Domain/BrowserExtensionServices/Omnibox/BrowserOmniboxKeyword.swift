import Foundation

/// The word a person types to hand the address bar over to a suggestion
/// provider.
///
/// Keywords are matched case-insensitively and cannot contain whitespace,
/// because the space is what separates the keyword from the rest of the query.
struct BrowserOmniboxKeyword:
    Comparable,
    Equatable,
    Hashable,
    RawRepresentable,
    Sendable
{
    let rawValue: String

    init?(_ rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty,
            !normalized.contains(where: \.isWhitespace)
        else {
            return nil
        }
        self.rawValue = normalized
    }

    init?(rawValue: String) {
        self.init(rawValue)
    }

    static func < (
        lhs: BrowserOmniboxKeyword,
        rhs: BrowserOmniboxKeyword
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
