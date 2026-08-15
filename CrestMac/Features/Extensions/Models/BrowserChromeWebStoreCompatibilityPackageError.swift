import Foundation

enum BrowserChromeWebStoreCompatibilityPackageError: LocalizedError {
    case invalidBackgroundManifest
    case unsafeBackgroundPath
    case archiveExpansionFailed

    var errorDescription: String? {
        switch self {
        case .invalidBackgroundManifest:
            "Crest couldn’t prepare this extension’s WebKit compatibility layer."
        case .unsafeBackgroundPath:
            "The extension declared an unsafe background script path."
        case .archiveExpansionFailed:
            "Crest couldn’t unpack this extension for WebKit compatibility."
        }
    }
}
