import Foundation

/// Tells the helper Crest is done. It has no reply, so it is not a request.
struct ApplePasswordsEndMessage {
    // MARK: - Actions - Encoding

    static func encoded() throws -> Data {
        try JSONEncoder().encode(Body(number: ApplePasswordsCommand.end.number))
    }

    // MARK: - Types

    private struct Body: Encodable {
        let number: Int

        private enum CodingKeys: String, CodingKey {
            case number = "cmd"
        }
    }
}
