import Foundation

enum BrowserExtensionControllerPoolError: LocalizedError {
    case invalidInstallationRecord
    case missingInstallation
    case unsupportedInstallationSource
    case unauthenticatedReplacement

    var errorDescription: String? {
        switch self {
        case .invalidInstallationRecord:
            "The extension produced invalid installation metadata."
        case .missingInstallation:
            "The extension installation could not be found."
        case .unsupportedInstallationSource:
            "This extension source isn’t available on this device."
        case .unauthenticatedReplacement:
            String(
                localized:
                    "This package cannot replace an extension from a different source. Remove the existing installation and its data before installing from this source."
            )
        }
    }
}
