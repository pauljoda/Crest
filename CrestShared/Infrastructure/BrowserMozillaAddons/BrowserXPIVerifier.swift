import CryptoKit
import Foundation

/// Checks that a downloaded add-on archive is the exact package its
/// addons.mozilla.org listing describes.
///
/// A Firefox add-on is a plain ZIP, so unlike a CRX3 it carries no identity in
/// its own container. The binding therefore comes from the listing: AMO
/// publishes the SHA-256 digest and byte count of the file it signed, and this
/// verifier refuses anything that does not reproduce both over a connection
/// that already terminated at `addons.mozilla.org`.
///
/// Mozilla's own JAR signature — `META-INF/mozilla.rsa` over
/// `META-INF/mozilla.sf` over `META-INF/manifest.mf` — is required to be
/// present, which rejects a side-loaded or self-built archive. Validating that
/// PKCS#7 chain against a pinned Mozilla root, and then walking the manifest
/// digests entry by entry, is deliberately not attempted here; a partial
/// signature check would imply a guarantee it does not deliver. See
/// `Documentation/ExtensionCompatibility.md` for that hardening follow-up.
struct BrowserXPIVerifier {
    static let maximumPackageByteCount = 64 * 1_024 * 1_024
    static let manifestEntryName = "manifest.json"
    static let signatureEntryNames: Set<String> = [
        "META-INF/manifest.mf",
        "META-INF/mozilla.rsa",
        "META-INF/mozilla.sf",
    ]

    private static let localFileHeaderSignature: [UInt8] = [
        0x50, 0x4b, 0x03, 0x04,
    ]

    func verify(
        _ archiveData: Data,
        expectedSHA256Hex: String,
        expectedByteCount: Int,
        extensionID: BrowserMozillaExtensionID
    ) throws -> BrowserVerifiedXPIPackage {
        guard archiveData.count <= Self.maximumPackageByteCount else {
            throw BrowserXPIVerifierError.packageTooLarge
        }
        guard archiveData.count == expectedByteCount else {
            throw BrowserXPIVerifierError.declaredSizeMismatch
        }
        guard archiveData.starts(with: Self.localFileHeaderSignature) else {
            throw BrowserXPIVerifierError.invalidArchive
        }
        let digest = Data(SHA256.hash(data: archiveData)).hexString
        guard digest == expectedSHA256Hex.lowercased() else {
            throw BrowserXPIVerifierError.digestMismatch
        }
        guard let entryNames = Self.entryNames(in: archiveData) else {
            throw BrowserXPIVerifierError.invalidArchive
        }
        guard entryNames.contains(Self.manifestEntryName) else {
            throw BrowserXPIVerifierError.missingManifest
        }
        // The JAR specification treats the signature block's own names as
        // case-insensitive, so both sides are folded before comparison.
        let foldedNames = Set(entryNames.map { $0.lowercased() })
        let requiredNames = Set(Self.signatureEntryNames.map { $0.lowercased() })
        guard requiredNames.isSubset(of: foldedNames) else {
            throw BrowserXPIVerifierError.missingMozillaSignature
        }
        return BrowserVerifiedXPIPackage(
            extensionID: extensionID,
            archiveData: archiveData,
            xpiSHA256Hex: digest
        )
    }

    /// Reads the archive's central directory for its entry names only.
    ///
    /// Nothing is inflated: the question here is which files the archive claims
    /// to contain, which is what proves Mozilla's signing artifacts are
    /// present. Returns nil when the central directory is not well formed.
    private static func entryNames(in archive: Data) -> Set<String>? {
        archive.withUnsafeBytes { raw -> Set<String>? in
            let bytes = raw.bindMemory(to: UInt8.self)
            let endRecordLength = 22
            let maximumCommentLength = 65_535
            guard bytes.count >= endRecordLength else { return nil }

            func readUInt16(_ index: Int) -> Int? {
                guard index >= 0, index + 2 <= bytes.count else { return nil }
                return Int(bytes[index]) | Int(bytes[index + 1]) << 8
            }

            func readUInt32(_ index: Int) -> Int? {
                guard index >= 0, index + 4 <= bytes.count else { return nil }
                return Int(bytes[index])
                    | Int(bytes[index + 1]) << 8
                    | Int(bytes[index + 2]) << 16
                    | Int(bytes[index + 3]) << 24
            }

            let scanFloor = max(
                0,
                bytes.count - endRecordLength - maximumCommentLength
            )
            var endRecord: Int?
            var scan = bytes.count - endRecordLength
            while scan >= scanFloor {
                if readUInt32(scan) == 0x0605_4b50 {
                    endRecord = scan
                    break
                }
                scan -= 1
            }
            guard let endRecord,
                let entryCount = readUInt16(endRecord + 10),
                let directorySize = readUInt32(endRecord + 12),
                let directoryStart = readUInt32(endRecord + 16),
                directoryStart + directorySize <= bytes.count
            else {
                return nil
            }

            let directoryEnd = directoryStart + directorySize
            var cursor = directoryStart
            var names: Set<String> = []
            for _ in 0..<entryCount {
                guard cursor + 46 <= directoryEnd,
                    readUInt32(cursor) == 0x0201_4b50,
                    let nameLength = readUInt16(cursor + 28),
                    let extraLength = readUInt16(cursor + 30),
                    let commentLength = readUInt16(cursor + 32)
                else {
                    return nil
                }
                let nameStart = cursor + 46
                guard nameStart + nameLength <= directoryEnd,
                    let name = String(
                        bytes: UnsafeBufferPointer(
                            rebasing: bytes[nameStart..<(nameStart + nameLength)]
                        ),
                        encoding: .utf8
                    )
                else {
                    return nil
                }
                names.insert(name)
                cursor = nameStart + nameLength + extraLength + commentLength
            }
            return names
        }
    }
}
