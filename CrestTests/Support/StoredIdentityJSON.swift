import Foundation

/// JSON views for the stored identity spelling contracts: what a value writes,
/// and the same document with its identities written bare.
enum StoredIdentityJSON {
    /// `id` in the stored spelling, as `JSONSerialization` reads it.
    static func wrapped(_ id: UUID) -> [String: String] {
        ["rawValue": id.uuidString]
    }

    /// The JSON document `value` encodes to.
    static func document(of value: some Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
    }

    /// `document` with every `{"rawValue": UUID}` identity written bare.
    static func bare(_ document: Any) -> Any {
        if let object = document as? [String: Any] {
            if object.count == 1, let raw = object["rawValue"] as? String, UUID(uuidString: raw) != nil {
                return raw
            }
            return object.mapValues(bare)
        }
        if let array = document as? [Any] {
            return array.map(bare)
        }
        return document
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from document: Any) throws -> Value {
        try JSONDecoder().decode(
            type, from: JSONSerialization.data(withJSONObject: document, options: .fragmentsAllowed))
    }
}
