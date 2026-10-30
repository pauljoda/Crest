import Foundation

/// One message from the helper, decoded once at the boundary. Fields a
/// command does not carry are nil; fields Crest does not read are not decoded.
struct ApplePasswordsInboundEnvelope: Decodable, Sendable {
    // MARK: - Types

    struct Payload: Decodable, Sendable {
        /// Base64 of the handshake's JSON, whichever byte encoding the helper uses elsewhere.
        let pake: String?
        let sealedMessage: ApplePasswordsSealedMessage?

        private enum CodingKeys: String, CodingKey {
            case pake = "PAKE"
            case sealedMessage = "SMSG"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pake = try container.decodeIfPresent(String.self, forKey: .pake)
            sealedMessage = try container.decodeIfPresent(SealedField.self, forKey: .sealedMessage)?.message
        }

        /// The handshake message inside `PAKE`.
        func handshakeMessage<Message: Decodable>(as type: Message.Type) throws -> Message {
            guard let pake, let json = Data(base64Encoded: pake),
                let message = try? JSONDecoder().decode(Message.self, from: json)
            else { throw ApplePasswordsError.malformedReply }
            return message
        }
    }

    /// The sealed message arrives as a JSON string or as an object; both mean the same.
    private struct SealedField: Decodable {
        let message: ApplePasswordsSealedMessage

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                message = try JSONDecoder().decode(ApplePasswordsSealedMessage.self, from: Data(text.utf8))
            } else {
                message = try container.decode(ApplePasswordsSealedMessage.self)
            }
        }
    }

    // MARK: - Variables

    let number: Int
    let capabilities: ApplePasswordsCapabilities?
    let payload: Payload?

    /// The command the number names, or nil for one the codec does not know.
    var command: ApplePasswordsCommand? { ApplePasswordsCommand.numbered(number) }

    private enum CodingKeys: String, CodingKey {
        case number = "cmd"
        case capabilities
        case payload
    }
}

/// A session identifier and the encrypted body it protects.
struct ApplePasswordsSealedMessage: Codable, Equatable, Sendable {
    let sessionIdentifier: String
    let sealedData: String

    private enum CodingKeys: String, CodingKey {
        case sessionIdentifier = "TID"
        case sealedData = "SDATA"
    }
}
