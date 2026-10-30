import Foundation

/// How accepting a completion edits the field: the suffix is typed after what
/// was typed when the accepted text only adds to it; otherwise the accepted
/// text, which names its scheme, replaces the field.
extension AddressCompletion {
    // MARK: - Variables

    var completedQuery: String { typed + suffix }

    var insertionText: String { accepted == completedQuery ? suffix : accepted }

    var insertionRange: NSRange {
        accepted == completedQuery
            ? NSRange(location: typed.utf16.count, length: 0)
            : NSRange(location: 0, length: typed.utf16.count)
    }

    // MARK: - Actions - Typing

    /// This completion for `text`: itself when `text` is what it completes,
    /// the rest of its suffix when `text` types further into that suffix, or
    /// nil when `text` leaves it or types all of it. The field keeps showing
    /// it while the core ranks the new text, so a keystroke that still
    /// matches never blanks it. As the core compares UTF-16 code units, the
    /// scheme and host match in any case and the path only exactly, so a
    /// path typed in another Unicode form leaves the completion.
    func continued(to text: String) -> AddressCompletion? {
        let typedUnits = Array(typed.utf16)
        let textUnits = Array(text.utf16)
        if textUnits == typedUnits { return self }
        guard textUnits.starts(with: typedUnits) else { return nil }
        let completed = Array(completedQuery.utf16)
        guard textUnits.count < completed.count else { return nil }
        let pathStart = Self.pathStart(of: completed)
        for position in typedUnits.count..<textUnits.count {
            let unit = textUnits[position]
            let expected = completed[position]
            let matches = position < pathStart ? Self.sameIgnoringCase(unit, expected) : unit == expected
            guard matches else { return nil }
        }
        return AddressCompletion(
            typed: text, suffix: String(decoding: completed[textUnits.count...], as: UTF16.self), accepted: accepted)
    }

    /// Where the path begins in `address`: its first `/` after an `http://`
    /// or `https://` it starts with, or its end when it has none.
    private static func pathStart(of address: [UTF16.CodeUnit]) -> Int {
        let scheme = ["https://", "http://"].first {
            String(decoding: address.prefix($0.utf16.count), as: UTF16.self).lowercased() == $0
        }
        let host = scheme?.utf16.count ?? 0
        return address[host...].firstIndex(of: UTF16.CodeUnit(UInt8(ascii: "/"))) ?? address.count
    }

    /// Whether two code units are the same once each is lowercased on its
    /// own, as the core lowercases a host; a surrogate matches only itself.
    private static func sameIgnoringCase(_ unit: UTF16.CodeUnit, _ other: UTF16.CodeUnit) -> Bool {
        if unit == other { return true }
        guard let scalar = Unicode.Scalar(unit), let otherScalar = Unicode.Scalar(other) else { return false }
        return String(scalar).lowercased() == String(otherScalar).lowercased()
    }
}
