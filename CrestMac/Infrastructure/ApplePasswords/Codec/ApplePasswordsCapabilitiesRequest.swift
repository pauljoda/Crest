import Foundation

/// Asks the helper what it supports. The first message of every launch.
struct ApplePasswordsCapabilitiesRequest: ApplePasswordsRequest {
    // MARK: - Variables

    var command: ApplePasswordsCommand { .getCapabilities }

    // MARK: - Actions - Encoding

    func encoded() throws -> Data {
        try JSONEncoder().encode(Body(number: command.number))
    }

    // MARK: - Actions - Decoding

    func reply(from envelope: ApplePasswordsInboundEnvelope) throws -> ApplePasswordsCapabilities {
        // A reply without capabilities names none, which is the empty set.
        envelope.capabilities
            ?? ApplePasswordsCapabilities(
                secretSessionVersion: nil,
                shouldUseBase64: nil,
                canFillOneTimeCodes: nil,
                canOpenPasswordsAppToNewPasswordSheet: nil,
                scanForOTPURI: nil,
                canSaveAccountWithEmptyUserName: nil
            )
    }

    // MARK: - Types

    private struct Body: Encodable {
        let number: Int

        private enum CodingKeys: String, CodingKey {
            case number = "cmd"
        }
    }
}
