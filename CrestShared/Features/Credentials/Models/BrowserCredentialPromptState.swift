import Foundation

enum BrowserCredentialPromptState: Equatable, Sendable {
    case preparing
    case create
    case update
    case alreadyStored
    case saving(BrowserCredentialSavePromptAction)
    case saved(BrowserCredentialSaveDisposition)
    case failedPreparation
    case failedCommit(BrowserCredentialSavePromptAction)
    case offeringToSystemPasswords
    case completedSystemPasswords
    case failedSystemPasswords
}
