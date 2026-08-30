import CryptoKit
import Foundation

struct BrowserExtensionRuntimeIdentity: Equatable, Sendable {
    let extensionID: String
    let uniqueIdentifier: String
    let baseURL: URL
    let referenceEnvironment: BrowserExtensionReferenceEnvironment

    init(
        extensionID: String,
        uniqueIdentifier: String,
        baseURL: URL,
        referenceEnvironment: BrowserExtensionReferenceEnvironment = .webKit
    ) {
        self.extensionID = extensionID
        self.uniqueIdentifier = uniqueIdentifier
        self.baseURL = baseURL
        self.referenceEnvironment = referenceEnvironment
    }
}

enum BrowserExtensionRuntimeIdentifierPolicy {
    // Preserve the origin class Chrome Web Store packages are authored for.
    // WebKit accepts any custom base-URL scheme, but cross-origin extension
    // requests are classified by their initiating scheme before host access
    // is applied. A branded scheme makes an otherwise reviewed extension look
    // like ordinary custom-scheme content at that boundary.
    static let urlScheme = "chrome-extension"

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
        // A verified Chrome package keeps its signed extension identifier,
        // but WebKit service-worker registrations are keyed by origin. Give
        // every Space a stable origin of its own so loading the same package
        // in a second controller cannot reuse the first Space's dormant
        // worker registration and silently lose its runtime listeners.
        let originIdentifier =
            "\(extensionID).space.\(spaceID.rawValue.uuidString.lowercased())"
        let digest = SHA256.hash(data: Data(originIdentifier.utf8))
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
            baseURL: baseURL,
            referenceEnvironment: referenceEnvironment(for: source)
        )
    }

    private static func referenceEnvironment(
        for source: BrowserExtensionInstallationSource?
    ) -> BrowserExtensionReferenceEnvironment {
        switch source {
        case .chromeWebStore:
            .chromium
        case .mozillaAddons:
            .firefox
        case .safariWebExtension:
            .webKit
        case .localPackage, .unpackedPackage, nil:
            .webKit
        }
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
