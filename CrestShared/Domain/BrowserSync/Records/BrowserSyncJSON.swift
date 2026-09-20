import Foundation

/// Opaque additive wire fields, never interpreted as browser state. Native
/// records are immutable read projections; the core decides which fields an
/// edit replaces. Keep integers exact rather than routing them through Double.
indirect enum BrowserSyncJSON: Codable, Equatable, Sendable {
    case object([String: Self]), array([Self]), string(String), bool(Bool)
    case integer(Int64), unsigned(UInt64), decimal(Decimal), floating(Double), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode(Int64.self) { self = .integer(v) }
        else if let v = try? value.decode(UInt64.self) { self = .unsigned(v) }
        else if let v = try? value.decode(Decimal.self) { self = .decimal(v) }
        else if let v = try? value.decode(Double.self) { self = .floating(v) }
        else if let v = try? value.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try value.decode([Self].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .integer(let v): try value.encode(v)
        case .unsigned(let v): try value.encode(v)
        case .decimal(let v): try value.encode(v)
        case .floating(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }

    static func encoded<T: Encodable>(_ value: T, using encoder: JSONEncoder = JSONEncoder()) throws -> Self {
        try JSONDecoder().decode(Self.self, from: encoder.encode(value))
    }

    private var identity: String? {
        guard case .object(let fields) = self, let id = fields["id"] else { return nil }
        if case .string(let id) = id { return id.lowercased() }
        if case .object(let wrapper) = id, case .string(let id) = wrapper["rawValue"] { return id.lowercased() }
        return nil
    }

    /// Extract only properties omitted by this version's typed decoder. Array
    /// members with identities follow their IDs, including normalized groups.
    func additions(to known: Self) -> Self? {
        switch (self, known) {
        case (.object(let source), .object(let known)):
            var result: [String: Self] = [:]
            for (key, value) in source {
                if let recognized = known[key] { result[key] = value.additions(to: recognized) }
                else { result[key] = value }
            }
            return result.isEmpty ? nil : .object(result)
        case (.array(let source), .array(let known)):
            var hasAdditions = false
            let result = known.enumerated().map { index, value -> Self in
                let original = value.identity.map { id in source.first { $0.identity == id } }
                    ?? (source.indices.contains(index) ? source[index] : nil)
                if let extra = original?.additions(to: value) { hasAdditions = true; return extra }
                return .object([:])
            }
            return hasAdditions ? .array(result) : nil
        default: return nil
        }
    }

    func adding(_ additions: Self?) -> Self {
        guard let additions else { return self }
        switch (self, additions) {
        case (.object(var values), .object(let extra)):
            for (key, value) in extra { values[key] = values[key]?.adding(value) ?? value }
            return .object(values)
        case (.array(let values), .array(let extra)):
            return .array(values.enumerated().map { index, value in
                value.adding(extra.indices.contains(index) ? extra[index] : nil)
            })
        default: return self
        }
    }
}
