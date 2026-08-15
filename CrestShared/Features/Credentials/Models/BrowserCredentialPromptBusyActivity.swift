import Foundation

enum BrowserCredentialPromptBusyActivity: Equatable, Sendable {
    case checkingSavedPasswords
    case savingPassword
    case openingSystemPasswords
}
