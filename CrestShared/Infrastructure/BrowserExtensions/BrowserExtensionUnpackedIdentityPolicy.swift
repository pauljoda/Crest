import CryptoKit
import Foundation

/// Derives the identity Crest gives an unpacked extension. It has no signed
/// store identifier, so the identity has to come from the package itself:
/// re-importing the same folder must land on the same registry row and keep its
/// pin, permissions, shortcuts, and WebKit storage rather than minting a second
/// installation beside the first.
enum BrowserExtensionUnpackedIdentityPolicy {
    static let prefix = "local."

    /// Number of hash bytes kept. Sixteen bytes is what Chrome uses to derive an
    /// extension ID, and it is far more than enough to keep one person's
    /// unpacked folders apart.
    private static let significantByteCount = 16

    static func extensionID(
        for sourceURL: URL,
        fileManager: FileManager = .default
    ) -> String {
        // A manifest `key` is the developer's own stable identity for the
        // package, so it survives the folder being moved or renamed.
        if let key = manifestKey(at: sourceURL, fileManager: fileManager) {
            return identifier(hashing: Data(key.utf8))
        }
        return identifier(hashing: Data(canonicalPath(for: sourceURL).utf8))
    }

    static func isUnpackedIdentifier(_ value: String) -> Bool {
        value.hasPrefix(prefix)
    }

    private static func identifier(hashing data: Data) -> String {
        let digest = Data(SHA256.hash(data: data))
            .prefix(significantByteCount)
        return prefix + Data(digest).hexString
    }

    private static func canonicalPath(for sourceURL: URL) -> String {
        sourceURL.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func manifestKey(
        at sourceURL: URL,
        fileManager: FileManager
    ) -> String? {
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(
                atPath: sourceURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue
        else {
            return nil
        }
        let manifestURL = sourceURL.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let key = manifest["key"] as? String
        else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
