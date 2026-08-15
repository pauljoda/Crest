enum BrowserCredentialFillError: Error, Equatable {
    case staleOrMismatchedRequest
    case formChanged
}
