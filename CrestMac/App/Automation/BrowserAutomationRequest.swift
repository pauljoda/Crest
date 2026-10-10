import Foundation

// MARK: - Types

/// The identity a tool gave a request, which its answer repeats.
enum BrowserAutomationRequestID: Codable, Sendable {
    case number(Int64)
    case string(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int64.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        }
    }
}

/// What every request carries before the method it names reads its
/// parameters.
private struct BrowserAutomationEnvelope: Decodable {
    let jsonrpc: String
    let id: BrowserAutomationRequestID?
    let method: String
}

/// A request's parameters as the method it names reads them.
private struct BrowserAutomationParameterEnvelope<Parameters: Decodable>: Decodable {
    let params: Parameters?
}

/// A response that answers a request. Its `id` is always written, as null
/// for a request that gave none.
private struct BrowserAutomationAnswer<Result: Encodable>: Encodable {
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result
    }

    let id: BrowserAutomationRequestID?
    let result: Result

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(result, forKey: .result)
    }
}

/// A response that refuses a request, with the reason a tool can match on.
/// Its `id` is always written, as null for a request whose identity could
/// not be read.
private struct BrowserAutomationRefusal: Encodable {
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, error
    }

    struct Detail: Encodable {
        let code: Int
        let message: String
        let data: Reason
    }

    struct Reason: Encodable {
        let reason: String
    }

    let id: BrowserAutomationRequestID?
    let error: Detail

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(error, forKey: .error)
    }
}

/// One request a tool sent: a JSON-RPC 2.0 request on a line of its own.
/// The envelope is read here; the method the request names reads its
/// parameters, absent ones as an empty object.
struct BrowserAutomationRequest {
    // MARK: - Static Variables

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    // MARK: - Variables

    let id: BrowserAutomationRequestID?
    let method: String
    private let line: Data

    // MARK: - Initializers

    /// Reads `line`, or throws the JSON-RPC error that refuses it.
    init(line: Data) throws(BrowserAutomationError) {
        let envelope: BrowserAutomationEnvelope
        do {
            envelope = try JSONDecoder().decode(BrowserAutomationEnvelope.self, from: line)
        } catch DecodingError.dataCorrupted(let context) where context.codingPath.isEmpty {
            throw .parseError
        } catch {
            throw .invalidRequest
        }
        guard envelope.jsonrpc == "2.0" else { throw .invalidRequest }
        id = envelope.id
        method = envelope.method
        self.line = line
    }

    // MARK: - Actions - Parameters

    /// The request's parameters as `Parameters`, or the error that names the
    /// one that does not read.
    func parameters<Parameters: Decodable>(_: Parameters.Type) throws(BrowserAutomationError) -> Parameters {
        do {
            let envelope = try JSONDecoder().decode(BrowserAutomationParameterEnvelope<Parameters>.self, from: line)
            return try envelope.params ?? JSONDecoder().decode(Parameters.self, from: Data("{}".utf8))
        } catch let error as DecodingError {
            throw .invalidParams(Self.explanation(of: error))
        } catch {
            throw .invalidParams(error.localizedDescription)
        }
    }

    /// What is wrong with the parameters, naming the one at fault.
    private static func explanation(of error: DecodingError) -> String {
        func name(_ path: [any CodingKey]) -> String {
            path.filter { $0.stringValue != "params" }.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "“\(name(context.codingPath + [key]))” is missing."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "“\(name(context.codingPath))” is not valid."
        @unknown default:
            return "The parameters are not valid."
        }
    }

    // MARK: - Actions - Responses

    /// The response that answers this request with `result`.
    func answer(_ result: some Encodable) -> Data {
        Self.encode(BrowserAutomationAnswer(id: id, result: result))
    }

    /// The response that refuses a request whose identity is `id`, or one
    /// whose identity could not be read, with `error`.
    static func refusal(_ error: BrowserAutomationError, id: BrowserAutomationRequestID?) -> Data {
        encode(
            BrowserAutomationRefusal(
                id: id,
                error: .init(code: error.code, message: error.message, data: .init(reason: error.reason))))
    }

    private static func encode(_ response: some Encodable) -> Data {
        (try? encoder.encode(response))
            ?? Data(#"{"error":{"code":-32603,"message":"Internal error"},"id":null,"jsonrpc":"2.0"}"#.utf8)
    }
}
