import CryptoKit
import Foundation

struct BrowserExtensionIconPayloadFactory: Sendable {
    typealias Validate = @Sendable (Data) -> Bool
    typealias Identify = @Sendable (Data) -> BrowserExtensionIconContentIdentifier

    static let production = Self(
        validate: BrowserExtensionIconEncodedDataValidator()
            .containsCompleteImage,
        identifier: sha256Identifier
    )

    private let validate: Validate
    private let identifier: Identify

    private init(
        validate: @escaping Validate,
        identifier: @escaping Identify
    ) {
        self.validate = validate
        self.identifier = identifier
    }

    #if DEBUG
        init(
            testingValidate: @escaping Validate,
            testingIdentifier: @escaping Identify
        ) {
            self.init(
                validate: testingValidate,
                identifier: testingIdentifier
            )
        }
    #endif

    func payload(for data: Data?) -> BrowserExtensionIconPayload? {
        guard let data,
            !data.isEmpty,
            data.count <= BrowserExtensionIconPayload.maximumEncodedByteCount,
            validate(data)
        else {
            return nil
        }
        return BrowserExtensionIconPayload(
            data: data,
            contentIdentifier: identifier(data)
        )
    }

    private static func sha256Identifier(
        _ data: Data
    ) -> BrowserExtensionIconContentIdentifier {
        let digest = SHA256.hash(data: data)
        return BrowserExtensionIconContentIdentifier(
            encodedByteCount: data.count,
            firstWord: word(in: digest, startingAt: 0),
            secondWord: word(in: digest, startingAt: 8),
            thirdWord: word(in: digest, startingAt: 16),
            fourthWord: word(in: digest, startingAt: 24)
        )
    }

    private static func word(
        in digest: SHA256.Digest,
        startingAt startIndex: Int
    ) -> UInt64 {
        digest.dropFirst(startIndex).prefix(8).reduce(0) { partial, byte in
            (partial << 8) | UInt64(byte)
        }
    }
}
