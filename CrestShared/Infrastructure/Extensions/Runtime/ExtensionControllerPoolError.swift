import Foundation

enum BrowserExtensionControllerPoolError: LocalizedError {
    case invalidInstallationRecord
    case missingInstallation
    case unsupportedInstallationSource

    var errorDescription: String? {
        switch self {
        case .invalidInstallationRecord:
            "The extension produced invalid installation metadata."
        case .missingInstallation:
            "The extension installation could not be found."
        case .unsupportedInstallationSource:
            "This extension source isn’t available on this device."
        }
    }
}
