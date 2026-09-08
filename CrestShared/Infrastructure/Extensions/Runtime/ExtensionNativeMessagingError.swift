import Foundation

enum BrowserExtensionCapabilityBrokerError: LocalizedError, Equatable {
    case invalidRequest
    case permissionDenied(String)
    case serviceFailure(String)
    case unsupportedAPI(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The extension sent Crest an invalid capability request."
        case .permissionDenied(let permission):
            "The extension does not have the \(permission) permission."
        case .serviceFailure(let description):
            description
        case .unsupportedAPI(let api):
            "Crest does not support the \(api) capability."
        }
    }
}

enum BrowserExtensionNativeMessagingError: LocalizedError {
    case unavailable
    case unverifiedExtension

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(
                localized: "Native companion messaging is unavailable in this build of Crest."
            )
        case .unverifiedExtension:
            String(
                localized: "Crest only allows verified Chrome Web Store extensions to contact native companion apps."
            )
        }
    }
}
