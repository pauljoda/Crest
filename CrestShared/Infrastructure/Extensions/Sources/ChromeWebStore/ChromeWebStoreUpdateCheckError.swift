import Foundation

enum BrowserChromeWebStoreUpdateCheckError: LocalizedError, Equatable {
    case transport(String)
    case invalidResponse
    case responseTooLarge
    case malformedDocument
    case identityMismatch
    case applicationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .transport(let description):
            "The Chrome Web Store update check failed: \(description)"
        case .invalidResponse:
            "The Chrome Web Store did not answer the update check."
        case .responseTooLarge:
            "The Chrome Web Store update check answer was unexpectedly large."
        case .malformedDocument:
            "Crest could not read the Chrome Web Store update check answer."
        case .identityMismatch:
            "The Chrome Web Store answered for a different extension."
        case .applicationUnavailable(let status):
            "The Chrome Web Store no longer publishes this extension (\(status))."
        }
    }
}
