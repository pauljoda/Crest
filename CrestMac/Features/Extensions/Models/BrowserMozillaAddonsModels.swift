import AppKit
import Foundation
import WebKit

struct BrowserMozillaAddonsCandidate: Identifiable, Sendable {
    let item: BrowserMozillaAddonsItem
    let source: BrowserMozillaAddonsSource
    let verifiedPackage: BrowserVerifiedXPIPackage
    let displayName: String
    let version: String?
    let displayDescription: String?
    let requestedPermissions: [String]
    let requestedHosts: [String]
    let errors: [String]
    let iconPayload: BrowserExtensionIconPayload?
    let hasOptionsPage: Bool
    let hasCommands: Bool
    let isMozillaRecommended: Bool
    let nativeMessagingCapability: BrowserExtensionNativeMessagingCapability

    var id: String { source.extensionID.rawValue }
    var iconData: Data? { iconPayload?.data }

    var compatibility: BrowserExtensionCompatibilityAssessment {
        BrowserExtensionCompatibilityPolicy.assess(
            extensionID: source.extensionID.rawValue,
            requestedPermissions: requestedPermissions,
            source: .mozillaAddons,
            nativeMessagingCapability: nativeMessagingCapability
        )
    }
}

enum BrowserMozillaAddonsProviderError: LocalizedError {
    case addonNotFound
    case extensionIdentityMismatch
    case invalidListingResponse
    case invalidPackageResponse
    case listingIdentityMismatch
    case packageTooLarge
    case transport(Error)
    case untrustedDownloadHost

    var errorDescription: String? {
        switch self {
        case .addonNotFound:
            "Firefox Add-ons has no listing for this add-on."
        case .extensionIdentityMismatch:
            "The downloaded add-on declares a different identity than its Firefox Add-ons listing."
        case .invalidListingResponse:
            "Firefox Add-ons did not return a usable listing for this add-on."
        case .invalidPackageResponse:
            "Firefox Add-ons did not return an add-on package."
        case .listingIdentityMismatch:
            "The Firefox Add-ons listing does not match the page this install came from."
        case .packageTooLarge:
            "The add-on package exceeds Crest’s safe import limits."
        case .transport(let error):
            "The Firefox Add-ons download failed: \(error.localizedDescription)"
        case .untrustedDownloadHost:
            "Firefox Add-ons redirected its download somewhere Crest does not trust."
        }
    }
}
