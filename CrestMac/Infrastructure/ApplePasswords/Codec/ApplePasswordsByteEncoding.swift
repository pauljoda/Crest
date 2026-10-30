import Foundation

/// How the helper spells a byte string in its JSON. The capabilities it
/// reports pick one: standard base64, or lowercase hexadecimal.
struct ApplePasswordsByteEncoding: Sendable {
    // MARK: - Static Variables

    static let base64 = ApplePasswordsByteEncoding(
        prefix: "",
        render: { $0.base64EncodedString() },
        parse: { Data(base64Encoded: $0) }
    )
    static let hexadecimal = ApplePasswordsByteEncoding(
        prefix: "0x",
        render: { $0.map { String(format: "%02x", $0) }.joined() },
        parse: ApplePasswordsByteEncoding.parseHexadecimal
    )

    // MARK: - Variables

    private let prefix: String
    private let render: @Sendable (Data) -> String
    private let parse: @Sendable (String) -> Data?

    // MARK: - Initializers

    private init(
        prefix: String,
        render: @escaping @Sendable (Data) -> String,
        parse: @escaping @Sendable (String) -> Data?
    ) {
        self.prefix = prefix
        self.render = render
        self.parse = parse
    }

    // MARK: - Actions - Encoding

    /// The spelling of `bytes`. A prefixed spelling is the form identifiers
    /// and public values use on the wire; the proof is unprefixed.
    func string(for bytes: Data, prefixed: Bool) -> String {
        (prefixed ? prefix : "") + render(bytes)
    }

    /// The bytes a spelling stands for. Hexadecimal drops one `0x` prefix and
    /// reads an odd number of digits as if it had a leading zero.
    func bytes(from string: String) throws -> Data {
        guard let bytes = parse(string) else { throw ApplePasswordsError.malformedReply }
        return bytes
    }

    private static func parseHexadecimal(_ string: String) -> Data? {
        var digits = Substring(string)
        if digits.hasPrefix("0x") { digits = digits.dropFirst(2) }
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if digits.count % 2 != 0 { digits = "0" + digits }
        var bytes = Data()
        bytes.reserveCapacity(digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
