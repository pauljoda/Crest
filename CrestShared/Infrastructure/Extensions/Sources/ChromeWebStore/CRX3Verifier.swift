import CryptoKit
import Foundation
import Security

struct BrowserCRX3Verifier: Sendable {
    static let maximumPackageByteCount = 64 * 1_024 * 1_024
    private static let maximumHeaderByteCount = 1 * 1_024 * 1_024
    private static let signedDataPrefix = Data("CRX3 SignedData\0".utf8)

    /// SHA-256 of Google's current CRX3 publisher proof public key, pinned by
    /// Chromium's own verifier for packages distributed by the Web Store.
    static let chromeWebStorePublisherKeyHash: Data = {
        guard
            let hash = Data(
                hexString:
                    "61f7f2a6bfcf74cd0bc1fe2497cc9b04254c658f79f2145392867ea8366367cf"
            )
        else {
            preconditionFailure("The pinned Chrome Web Store publisher key hash is invalid.")
        }
        return hash
    }()

    let requiredPublisherKeyHash: Data

    init(
        requiredPublisherKeyHash: Data = Self.chromeWebStorePublisherKeyHash
    ) {
        precondition(requiredPublisherKeyHash.count == SHA256.byteCount)
        self.requiredPublisherKeyHash = requiredPublisherKeyHash
    }

    func verify(
        _ crxData: Data,
        expectedID: BrowserChromeExtensionID
    ) throws -> BrowserVerifiedCRX3Package {
        try verify(crxData, expectedID: Optional(expectedID))
    }

    /// Verifies a directly selected CRX3 package and trusts only the identity
    /// carried by its signed header. The Chrome Web Store publisher proof is
    /// still mandatory, so choosing a file never weakens the store install
    /// path into accepting a self-signed lookalike.
    func verify(_ crxData: Data) throws -> BrowserVerifiedCRX3Package {
        try verify(crxData, expectedID: nil)
    }

    private func verify(
        _ crxData: Data,
        expectedID: BrowserChromeExtensionID?
    ) throws -> BrowserVerifiedCRX3Package {
        guard crxData.count <= Self.maximumPackageByteCount else {
            throw BrowserCRX3VerifierError.packageTooLarge
        }
        guard crxData.count >= 16,
            crxData.prefix(4) == Data("Cr24".utf8),
            littleEndianUInt32(in: crxData, at: 4) == 3
        else {
            throw BrowserCRX3VerifierError.invalidArchive
        }
        let headerLength = Int(littleEndianUInt32(in: crxData, at: 8))
        guard headerLength > 0,
            headerLength <= Self.maximumHeaderByteCount,
            12 + headerLength < crxData.count
        else {
            throw BrowserCRX3VerifierError.invalidHeader
        }
        let header = Data(crxData[12..<12 + headerLength])
        let zipArchive = Data(crxData[(12 + headerLength)...])
        guard zipArchive.starts(with: [0x50, 0x4b, 0x03, 0x04]) else {
            throw BrowserCRX3VerifierError.invalidArchive
        }

        let headerFields = try BrowserCRX3ProtobufFields(data: header)
        let signedHeaders = headerFields.lengthDelimitedValues(for: 10_000)
        guard signedHeaders.count == 1 else {
            throw BrowserCRX3VerifierError.invalidHeader
        }
        let signedHeader = signedHeaders[0]
        let signedFields = try BrowserCRX3ProtobufFields(data: signedHeader)
        let declaredIDs = signedFields.lengthDelimitedValues(for: 1)
        guard declaredIDs.count == 1, declaredIDs[0].count == 16 else {
            throw BrowserCRX3VerifierError.invalidHeader
        }
        guard
            let declaredID = BrowserChromeExtensionID(
                Self.extensionID(from: declaredIDs[0])
            )
        else {
            throw BrowserCRX3VerifierError.invalidHeader
        }
        guard expectedID == nil || declaredID == expectedID else {
            throw BrowserCRX3VerifierError.extensionIDMismatch
        }

        var message = Self.signedDataPrefix
        message += Self.littleEndianData(UInt32(signedHeader.count))
        message += signedHeader
        message += zipArchive

        let rsaProofs = try proofs(
            from: headerFields.lengthDelimitedValues(for: 2),
            scheme: .rsa,
            message: message
        )
        let ecdsaProofs = try proofs(
            from: headerFields.lengthDelimitedValues(for: 3),
            scheme: .ecdsaP256,
            message: message
        )
        let allProofs = rsaProofs + ecdsaProofs
        guard
            allProofs.contains(where: {
                guard
                    let proofID = Self.extensionID(
                        fromPublicKey: $0.publicKey
                    )
                else {
                    return false
                }
                return proofID == declaredID
            })
        else {
            throw BrowserCRX3VerifierError.missingDeveloperProof
        }
        guard
            allProofs.contains(where: {
                Data(SHA256.hash(data: $0.publicKey))
                    == requiredPublisherKeyHash
            })
        else {
            throw BrowserCRX3VerifierError.missingPublisherProof
        }

        return BrowserVerifiedCRX3Package(
            extensionID: declaredID,
            crxData: crxData,
            zipArchiveData: zipArchive,
            crxSHA256Hex: Data(SHA256.hash(data: crxData)).hexString,
            publisherKeyHashHex: requiredPublisherKeyHash.hexString
        )
    }

    private func proofs(
        from encodedProofs: [Data],
        scheme: BrowserCRX3SignatureScheme,
        message: Data
    ) throws -> [BrowserCRX3VerifiedProof] {
        try encodedProofs.map { encodedProof in
            let fields = try BrowserCRX3ProtobufFields(data: encodedProof)
            let publicKeys = fields.lengthDelimitedValues(for: 1)
            let signatures = fields.lengthDelimitedValues(for: 2)
            guard publicKeys.count == 1,
                signatures.count == 1,
                !publicKeys[0].isEmpty,
                !signatures[0].isEmpty
            else {
                throw BrowserCRX3VerifierError.invalidHeader
            }
            guard
                verify(
                    signature: signatures[0],
                    publicKey: publicKeys[0],
                    scheme: scheme,
                    message: message
                )
            else {
                throw BrowserCRX3VerifierError.invalidSignature
            }
            return BrowserCRX3VerifiedProof(publicKey: publicKeys[0])
        }
    }

    private func verify(
        signature: Data,
        publicKey: Data,
        scheme: BrowserCRX3SignatureScheme,
        message: Data
    ) -> Bool {
        switch scheme {
        case .rsa:
            let attributes: [CFString: Any] = [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPublic,
            ]
            var importError: Unmanaged<CFError>?
            guard
                let key = SecKeyCreateWithData(
                    publicKey as CFData,
                    attributes as CFDictionary,
                    &importError
                )
            else {
                return false
            }
            var verificationError: Unmanaged<CFError>?
            return SecKeyVerifySignature(
                key,
                .rsaSignatureMessagePKCS1v15SHA256,
                message as CFData,
                signature as CFData,
                &verificationError
            )
        case .ecdsaP256:
            guard
                let key = try? P256.Signing.PublicKey(
                    derRepresentation: publicKey
                ),
                let signature = try? P256.Signing.ECDSASignature(
                    derRepresentation: signature
                )
            else {
                return false
            }
            return key.isValidSignature(signature, for: message)
        }
    }

    private func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func littleEndianData(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func extensionID(
        fromPublicKey publicKey: Data
    ) -> BrowserChromeExtensionID? {
        let hash = Data(SHA256.hash(data: publicKey))
        return BrowserChromeExtensionID(
            extensionID(from: Data(hash.prefix(16)))
        )
    }

    private static func extensionID(from bytes: Data) -> String {
        let alphabet = Array("abcdefghijklmnop")
        return String(
            bytes.flatMap { byte in
                [
                    alphabet[Int(byte >> 4)],
                    alphabet[Int(byte & 0x0f)],
                ]
            })
    }

}
