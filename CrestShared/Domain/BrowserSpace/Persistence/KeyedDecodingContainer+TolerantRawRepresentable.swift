import Foundation

extension KeyedDecodingContainer {
    /// Decodes a string-backed vocabulary term, absorbing a term this build has
    /// never heard of.
    ///
    /// Crest's Spaces ride CloudKit, and a record whose payload refuses to decode
    /// does not merely arrive empty — it throws out of the fetch handler and takes
    /// the whole fetched batch with it, leaving sync in a failed state. A crest is
    /// decoration; it must never be the reason a Space fails to arrive. So an
    /// unrecognized term resolves to the caller's stated default and the rest of
    /// the record decodes normally.
    ///
    /// This is forward tolerance only. It protects *future* additions to a
    /// vocabulary; it cannot retroactively teach an already-shipped build to
    /// absorb terms added after it.
    func decodeTolerantly<Value>(
        _ key: Key,
        default fallback: Value
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = try? decodeIfPresent(String.self, forKey: key) else {
            return fallback
        }
        return Value(rawValue: rawValue) ?? fallback
    }
}
