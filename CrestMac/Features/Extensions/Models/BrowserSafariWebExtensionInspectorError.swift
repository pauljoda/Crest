import AppKit
import Foundation
import Security
import WebKit

enum BrowserSafariWebExtensionInspectorError: LocalizedError {
    case noWebExtensions(applicationName: String)
    case invalidCodeSignature(itemName: String)
    case missingExtensionBundle

    var errorDescription: String? {
        switch self {
        case .noWebExtensions(let applicationName):
            "\(applicationName) doesn’t contain a Safari Web Extension that Crest can use. Safari App Extensions and legacy content blockers aren’t compatible."
        case .invalidCodeSignature(let itemName):
            "\(itemName) doesn’t have a valid code signature. Crest only loads Safari Web Extensions from signed apps."
        case .missingExtensionBundle:
            "The Safari Web Extension could not be found inside its app."
        }
    }
}
