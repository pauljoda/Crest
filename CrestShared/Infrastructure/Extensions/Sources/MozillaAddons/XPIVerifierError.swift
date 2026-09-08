import Foundation

enum BrowserXPIVerifierError: LocalizedError, Equatable {
    case declaredSizeMismatch
    case digestMismatch
    case invalidArchive
    case missingManifest
    case missingMozillaSignature
    case packageTooLarge

    var errorDescription: String? {
        switch self {
        case .declaredSizeMismatch:
            "The downloaded add-on is not the size Firefox Add-ons published for it."
        case .digestMismatch:
            "The downloaded add-on does not match the checksum Firefox Add-ons published for it."
        case .invalidArchive:
            "Firefox Add-ons returned an invalid add-on archive."
        case .missingManifest:
            "The add-on archive has no manifest and cannot be loaded."
        case .missingMozillaSignature:
            "The add-on archive is not signed by Mozilla."
        case .packageTooLarge:
            "The add-on package exceeds Crest’s safe import limits."
        }
    }
}
