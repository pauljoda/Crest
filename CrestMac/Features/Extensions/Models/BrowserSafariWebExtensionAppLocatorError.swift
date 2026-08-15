import Foundation

enum BrowserSafariWebExtensionAppLocatorError: LocalizedError, Equatable {
    case invalidApplication
    case unreadableApplication

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            "Choose an installed application that contains a Safari Web Extension."
        case .unreadableApplication:
            "Crest couldn’t inspect that application."
        }
    }
}
