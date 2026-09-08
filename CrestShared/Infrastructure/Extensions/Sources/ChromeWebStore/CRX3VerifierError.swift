import Foundation

enum BrowserCRX3VerifierError: LocalizedError, Equatable {
    case extensionIDMismatch
    case invalidArchive
    case invalidHeader
    case invalidSignature
    case missingDeveloperProof
    case missingPublisherProof
    case packageTooLarge

    var errorDescription: String? {
        switch self {
        case .extensionIDMismatch:
            "The downloaded extension identity does not match its Chrome Web Store listing."
        case .invalidArchive, .invalidHeader:
            "The Chrome Web Store returned an invalid CRX3 package."
        case .invalidSignature:
            "The Chrome Web Store package signature could not be verified."
        case .missingDeveloperProof:
            "The CRX3 package is missing its developer identity proof."
        case .missingPublisherProof:
            "The CRX3 package was not signed by the Chrome Web Store."
        case .packageTooLarge:
            "The extension package exceeds Crest’s safe import limits."
        }
    }
}
