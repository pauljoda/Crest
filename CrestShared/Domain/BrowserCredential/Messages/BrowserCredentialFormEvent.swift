import Foundation

enum BrowserCredentialFormEvent: String, Equatable, Sendable {
    case username
    case focus
    case submit
    case documentState
}
