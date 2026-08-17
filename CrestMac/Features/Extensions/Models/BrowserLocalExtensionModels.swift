import Foundation

struct BrowserLocalExtensionCandidate: Identifiable, Sendable {
    let package: BrowserLocalExtensionPackage
    let displayName: String
    let version: String?
    let displayDescription: String?
    let requestedPermissions: [String]
    let requestedHosts: [String]
    let errors: [String]
    let iconPayload: BrowserExtensionIconPayload?
    let hasOptionsPage: Bool
    let hasCommands: Bool
    let nativeMessagingCapability: BrowserExtensionNativeMessagingCapability

    var id: String { package.extensionID }
    var iconData: Data? { iconPayload?.data }
    var format: BrowserLocalExtensionPackageFormat { package.format }

    var source: BrowserLocalExtensionSource {
        BrowserLocalExtensionSource(
            extensionID: package.extensionID,
            format: package.format,
            sha256Hex: package.sha256Hex
        )
    }

    var compatibility: BrowserExtensionCompatibilityAssessment {
        BrowserExtensionCompatibilityPolicy.assess(
            extensionID: package.extensionID,
            requestedPermissions: requestedPermissions,
            source: .unpackedPackage,
            nativeMessagingCapability: nativeMessagingCapability
        )
    }
}

enum BrowserLocalExtensionProviderError: LocalizedError, Equatable {
    case invalidArchive
    case invalidFirefoxIdentity
    case packageTooLarge
    case symbolicLink
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            String(localized: "The selected file is not a valid extension package.")
        case .invalidFirefoxIdentity:
            String(localized: "The Firefox package declares an invalid extension identity.")
        case .packageTooLarge:
            String(localized: "The extension package exceeds Crest’s safe import limits.")
        case .symbolicLink:
            String(localized: "Choose the extension package itself instead of a symbolic link.")
        case .unsupportedFileType:
            String(localized: "Choose a Chrome CRX or Firefox XPI package.")
        }
    }
}
