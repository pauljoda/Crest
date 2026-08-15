import Foundation

enum BrowserChromeWebStoreUpdaterError: LocalizedError {
    case unavailableRuntime
    case missingSpace
    case missingInstallation
    case unverifiableSource
    case identityMismatch

    var errorDescription: String? {
        switch self {
        case .unavailableRuntime:
            "Crest’s extension runtime is no longer available."
        case .missingSpace:
            "The Space that installed this extension is no longer open."
        case .missingInstallation:
            "This extension is no longer installed in that Space."
        case .unverifiableSource:
            "Crest cannot confirm which Chrome Web Store page installed this extension."
        case .identityMismatch:
            "The Chrome Web Store returned a package for a different extension."
        }
    }
}
