import Foundation

enum BrowserCredentialPromptPrimaryAction: Equatable, Sendable {
    case commit(BrowserCredentialSavePromptAction)
    case retryCredentialPreparation
    case retrySystemPasswords
}
