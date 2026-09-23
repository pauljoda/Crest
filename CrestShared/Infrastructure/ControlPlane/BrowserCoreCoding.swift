import Foundation

// A wrapped member initializes from its plain value only through a declared
// `init(wrappedValue:)`; the synthesized memberwise one does not count.
// swift-format-ignore: UseSynthesizedInitializer
/// A request member the core reads as present even when it has no value. It
/// encodes `nil` as an explicit JSON `null` instead of omitting the key, which
/// is what core decoders that look a member up unconditionally require.
@propertyWrapper
struct BrowserCoreNullable<Value: Encodable>: Encodable {
    // MARK: - Variables

    var wrappedValue: Value?

    // MARK: - Initializers

    init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    // MARK: - Actions - Encoding

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

extension BrowserCoreNullable: Sendable where Value: Sendable {}

/// An answer member read tolerantly: a missing, `null` or mistyped value reads
/// as `nil` rather than failing the whole answer. Members a caller requires stay
/// plain properties, so a malformed answer still reads as no answer.
@propertyWrapper
struct BrowserCoreOptional<Value: Decodable>: Decodable {
    // MARK: - Variables

    var wrappedValue: Value?

    // MARK: - Initializers

    init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: any Decoder) throws {
        wrappedValue = try? decoder.singleValueContainer().decode(Value.self)
    }
}

extension BrowserCoreOptional: Sendable where Value: Sendable {}

extension KeyedDecodingContainer {
    /// A tolerant member may also be absent.
    func decode<Value>(_ type: BrowserCoreOptional<Value>.Type, forKey key: Key) throws
        -> BrowserCoreOptional<Value>
    {
        BrowserCoreOptional(wrappedValue: (try? decodeIfPresent(Value.self, forKey: key)) ?? nil)
    }
}

/// A list answer that keeps the elements this build understands, so a value a
/// newer core adds is skipped rather than failing the whole list.
struct BrowserCoreKnownValues<Element: Decodable>: Decodable {
    // MARK: - Variables

    let values: [Element]

    // MARK: - Initializers

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        while !container.isAtEnd {
            if let value = try container.decode(BrowserCoreOptional<Element>.self).wrappedValue {
                values.append(value)
            }
        }
        self.values = values
    }
}

extension BrowserCoreKnownValues: Sendable where Element: Sendable {}

/// A JSON value the core owns and the native side only relays, such as the
/// state a progress estimator hands back on its next reading. Integers keep
/// their exact value; nothing here interprets the contents.
enum BrowserCoreOpaqueValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([BrowserCoreOpaqueValue])
    case object([String: BrowserCoreOpaqueValue])

    // MARK: - Initializers

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([BrowserCoreOpaqueValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: BrowserCoreOpaqueValue].self))
        }
    }

    // MARK: - Actions - Encoding

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// A command or query without arguments of its own.
struct BrowserCoreNoArguments: Encodable, Sendable {}

extension UUID {
    /// The spelling core policy and ledger requests require for identities.
    var coreIdentifier: String { uuidString.lowercased() }
}
