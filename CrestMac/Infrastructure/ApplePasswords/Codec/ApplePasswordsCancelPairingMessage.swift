import Foundation

/// Tells the helper the person gave up on the code, as Apple's extension does
/// when its pairing popup closes. It has no reply, so it is not a request.
struct ApplePasswordsCancelPairingMessage {
    // MARK: - Actions - Encoding

    static func encoded() throws -> Data {
        try JSONEncoder().encode(Body(number: ApplePasswordsCommand.cancelPairing.number))
    }

    // MARK: - Types

    private struct Body: Encodable {
        let number: Int

        private enum CodingKeys: String, CodingKey {
            case number = "cmd"
        }
    }
}
