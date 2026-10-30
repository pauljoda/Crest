import Foundation

/// The helper's framing on stdin and stdout: a four-byte little-endian length,
/// then that many bytes of UTF-8 JSON. The stream accumulates what the pipe
/// delivers and hands back whole frames; a length it cannot accept is fatal.
struct ApplePasswordsFrameStream {
    // MARK: - Static Variables

    /// No message in this protocol comes near a mebibyte.
    static let maximumPayloadLength = 1 << 20
    private static let lengthPrefixSize = 4

    // MARK: - Variables

    private var buffer: [UInt8] = []

    // MARK: - Actions - Encoding

    /// The bytes to write for one message.
    static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximumPayloadLength else {
            throw ApplePasswordsError.malformedReply
        }
        var length = UInt32(payload.count).littleEndian
        var framed = Data(bytes: &length, count: lengthPrefixSize)
        framed.append(payload)
        return framed
    }

    // MARK: - Actions - Decoding

    /// Takes what arrived and returns the payloads it completes, in order.
    /// Throws on a length that is zero or over the cap, which the caller
    /// treats as the helper breaking the protocol.
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(contentsOf: data)
        var payloads: [Data] = []
        while buffer.count >= Self.lengthPrefixSize {
            let length =
                Int(buffer[0]) | Int(buffer[1]) << 8 | Int(buffer[2]) << 16 | Int(buffer[3]) << 24
            guard length > 0, length <= Self.maximumPayloadLength else {
                buffer.removeAll()
                throw ApplePasswordsError.malformedReply
            }
            let end = Self.lengthPrefixSize + length
            guard buffer.count >= end else { break }
            payloads.append(Data(buffer[Self.lengthPrefixSize..<end]))
            buffer.removeFirst(end)
        }
        return payloads
    }
}
