import Foundation

/// What the helper says it can do, from its reply to the capabilities request.
/// Every field is optional and unknown keys are ignored.
struct ApplePasswordsCapabilities: Codable, Equatable, Sendable {
    // MARK: - Static Variables

    /// The secret session version Crest implements: SRP with RFC verification.
    private static let supportedSecretSessionVersion = 1

    // MARK: - Variables

    let secretSessionVersion: Int?
    let shouldUseBase64: Bool?
    let canFillOneTimeCodes: Bool?
    let canOpenPasswordsAppToNewPasswordSheet: Bool?
    let scanForOTPURI: Bool?
    let canSaveAccountWithEmptyUserName: Bool?

    /// A helper that names another session version is not one Crest can pair
    /// with; one that names none is taken to speak the supported one, as it
    /// negotiates the version again in the handshake.
    var isRecognized: Bool {
        secretSessionVersion == nil || secretSessionVersion == Self.supportedSecretSessionVersion
    }

    /// Hexadecimal unless the helper asks for base64.
    var byteEncoding: ApplePasswordsByteEncoding {
        shouldUseBase64 == true ? .base64 : .hexadecimal
    }
}
