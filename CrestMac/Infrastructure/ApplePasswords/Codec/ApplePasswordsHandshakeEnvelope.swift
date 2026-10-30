import Foundation

/// The outer message of both handshake requests: the handshake command around
/// a JSON string holding a query identifier and the base64 of the step's JSON.
struct ApplePasswordsHandshakeEnvelope: Encodable {
    // MARK: - Types

    private struct Message: Encodable {
        let queryID: String
        let pake: String
        let browser: String?

        private enum CodingKeys: String, CodingKey {
            case queryID = "QID"
            case pake = "PAKE"
            case browser = "HSTBRSR"
        }
    }

    // MARK: - Variables

    private let message: Message

    // MARK: - Initializers

    /// - Parameters:
    ///   - queryID: Names the step: `m0` opens the handshake, `m2` proves the code.
    ///   - step: The step's own JSON. It is always standard base64 on the wire,
    ///     whichever byte encoding the helper uses for byte strings.
    ///   - browser: The browser the helper shows beside the code. Only the first step names one.
    init(queryID: String, step: some Encodable, browser: String?) throws {
        message = Message(queryID: queryID, pake: try Self.base64(of: step), browser: browser)
    }

    // MARK: - Actions - Encoding

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ApplePasswordsCommand.handshake.number, forKey: .number)
        // Like the extension, the message travels as a JSON string, not an object.
        let text = try String(decoding: JSONEncoder().encode(message), as: UTF8.self)
        try container.encode(text, forKey: .message)
    }

    private static func base64(of step: some Encodable) throws -> String {
        try JSONEncoder().encode(step).base64EncodedString()
    }

    private enum CodingKeys: String, CodingKey {
        case number = "cmd"
        case message = "msg"
    }
}
