enum BrowserCredentialSavePromptFailure: Equatable, Sendable {
    case preparation
    case commit(BrowserCredentialSavePromptAction)
}
