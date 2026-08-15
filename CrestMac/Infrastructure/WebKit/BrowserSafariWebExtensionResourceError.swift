import Foundation
import Security
import WebKit

enum BrowserSafariWebExtensionResourceError: LocalizedError {
    case hostAppChanged
    case extensionMoved
    case invalidSignature
    case signerChanged

    var errorDescription: String? {
        switch self {
        case .hostAppChanged:
            "The app hosting this extension has changed. Add it again to continue."
        case .extensionMoved:
            "The Safari Web Extension is no longer present in its app."
        case .invalidSignature:
            "The Safari Web Extension no longer has a valid code signature."
        case .signerChanged:
            "The Safari Web Extension is now signed by a different developer. Add it again if you trust the new version."
        }
    }
}
