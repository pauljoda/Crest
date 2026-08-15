import Foundation

/// Ordering for Chrome extension version strings.
///
/// A Chrome manifest version is one to four dot-separated integers, each in
/// `0…65535`. Comparison is numeric per component with the shorter side
/// zero-padded, so `1.10` sorts above `1.9` and `2.0` equals `2.0.0`.
///
/// The parsing rules are deliberately strict in one direction: a store
/// version Crest cannot read never wins. An unparsable string arriving over
/// the network must not be able to talk Crest into replacing a working
/// installation.
enum BrowserExtensionVersionPolicy {
    static let maximumComponentCount = 4
    static let maximumComponentValue: UInt32 = 65_535

    /// Orders two version strings, or returns `nil` when either side is not a
    /// well-formed Chrome version.
    static func compare(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult? {
        guard let left = components(of: lhs),
            let right = components(of: rhs)
        else {
            return nil
        }
        for index in 0..<max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Whether `offered` should replace `installed`.
    ///
    /// An unreadable or absent installed version still upgrades, because a
    /// well-formed store version is strictly better information than a record
    /// Crest cannot interpret, and the replacement rewrites the record with a
    /// version it can read. An unreadable *offered* version never upgrades.
    static func isUpgrade(from installed: String?, to offered: String) -> Bool {
        guard components(of: offered) != nil else { return false }
        guard let installed, components(of: installed) != nil else {
            return true
        }
        return compare(offered, installed) == .orderedDescending
    }

    private static func components(of version: String) -> [UInt32]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fields = trimmed.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard (1...maximumComponentCount).contains(fields.count) else {
            return nil
        }
        var values: [UInt32] = []
        values.reserveCapacity(fields.count)
        for field in fields {
            guard !field.isEmpty,
                field.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                let value = UInt32(field),
                value <= maximumComponentValue
            else {
                return nil
            }
            values.append(value)
        }
        return values
    }
}
