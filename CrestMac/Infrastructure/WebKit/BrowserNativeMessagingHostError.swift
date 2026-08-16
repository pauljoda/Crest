import Foundation
import WebKit

enum BrowserNativeMessagingHostError: LocalizedError, Equatable {
    case invalidHostName
    case unnamedHostUnavailable
    case hostNotFound(String)
    case invalidManifest
    case originNotAllowed
    case invalidMessage
    case messageTooLarge
    case launchFailed(String)
    case timedOut
    case disconnected

    var errorDescription: String? {
        switch self {
        case .invalidHostName:
            "The extension requested an invalid native companion name."
        case .unnamedHostUnavailable:
            "Crest could not choose a unique native companion for this extension."
        case .hostNotFound(let name):
            "The native companion \(name) is not installed."
        case .invalidManifest:
            "The native companion has an invalid manifest."
        case .originNotAllowed:
            "The native companion does not allow this extension."
        case .invalidMessage:
            "The native companion sent an invalid message."
        case .messageTooLarge:
            "The native companion message exceeded the allowed size."
        case .launchFailed(let reason):
            "The native companion could not be started: \(reason)"
        case .timedOut:
            "The native companion did not answer in time."
        case .disconnected:
            "The native companion disconnected."
        }
    }
}
