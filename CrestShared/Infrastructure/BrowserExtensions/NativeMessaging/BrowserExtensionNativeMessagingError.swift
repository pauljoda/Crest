import Foundation

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
