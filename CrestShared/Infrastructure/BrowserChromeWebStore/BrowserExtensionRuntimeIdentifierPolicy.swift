import CryptoKit
import Foundation

struct BrowserExtensionRuntimeIdentity: Equatable, Sendable {
    let extensionID: String
    let uniqueIdentifier: String
    let baseURL: URL
}

enum BrowserExtensionRuntimeIdentifierPolicy {
    static let urlScheme = "crest-extension"

    static func identity(
        extensionID: String,
        source: BrowserExtensionInstallationSource?,
        spaceID: SpaceID
    ) -> BrowserExtensionRuntimeIdentity {
        let uniqueIdentifier = identifier(
            extensionID: extensionID,
            source: source,
            spaceID: spaceID
        )
        let digest = SHA256.hash(data: Data(uniqueIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard
            let baseURL = URL(
                string: "\(urlScheme)://extension-\(digest)/"
            )
        else {
            preconditionFailure("Unable to construct extension runtime URL")
        }
        return BrowserExtensionRuntimeIdentity(
            extensionID: extensionID,
            uniqueIdentifier: uniqueIdentifier,
            baseURL: baseURL
        )
    }

    static func identifier(
        extensionID: String,
        source: BrowserExtensionInstallationSource?,
        spaceID: SpaceID
    ) -> String {
        if case .chromeWebStore(let chromeSource) = source,
            chromeSource.extensionID.rawValue == extensionID
        {
            return extensionID
        }
        return "\(extensionID).space.\(spaceID.rawValue.uuidString.lowercased())"
    }
}
