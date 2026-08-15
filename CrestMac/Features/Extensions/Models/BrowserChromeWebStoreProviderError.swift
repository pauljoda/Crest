import AppKit
import Foundation
import WebKit

enum BrowserChromeWebStoreProviderError: LocalizedError {
    case invalidResponse
    case packageTooLarge
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The Chrome Web Store did not return an extension package."
        case .packageTooLarge:
            "The extension package exceeds Crest’s safe import limits."
        case .transport(let error):
            "The Chrome Web Store download failed: \(error.localizedDescription)"
        }
    }
}
