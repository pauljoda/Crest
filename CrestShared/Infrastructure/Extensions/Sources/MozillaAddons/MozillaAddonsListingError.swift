import Foundation

enum BrowserMozillaAddonsListingError: LocalizedError, Equatable {
    case malformedPayload
    case unknownAddon
    case unavailableAddon
    case unsupportedAddonType
    case missingCurrentVersion
    case invalidExtensionID
    case invalidSlug
    case invalidDownloadURL
    case unsupportedDigest

    var errorDescription: String? {
        switch self {
        case .malformedPayload:
            "Firefox Add-ons returned a listing Crest could not read."
        case .unknownAddon:
            "Firefox Add-ons has no listing for this add-on."
        case .unavailableAddon:
            "This add-on is no longer available on Firefox Add-ons."
        case .unsupportedAddonType:
            "Crest can only install Firefox extensions, not themes or language packs."
        case .missingCurrentVersion:
            "This Firefox Add-ons listing has no published version to install."
        case .invalidExtensionID:
            "The Firefox Add-ons listing reported an unusable add-on identity."
        case .invalidSlug:
            "The Firefox Add-ons listing reported an unusable add-on name."
        case .invalidDownloadURL:
            "The Firefox Add-ons listing points its download somewhere Crest does not trust."
        case .unsupportedDigest:
            "The Firefox Add-ons listing did not publish a SHA-256 digest for its package."
        }
    }
}
