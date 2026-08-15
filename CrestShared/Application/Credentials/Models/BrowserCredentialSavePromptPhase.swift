enum BrowserCredentialSavePromptPhase: Equatable, Sendable {
    case preparing
    case create
    case update
    case alreadyStored
    case saving(BrowserCredentialSavePromptAction)
    case saved(BrowserCredentialSaveDisposition)
    case failed(BrowserCredentialSavePromptFailure)
}
