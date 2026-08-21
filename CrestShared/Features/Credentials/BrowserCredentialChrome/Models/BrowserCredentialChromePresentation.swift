enum BrowserCredentialChromePresentation: Equatable {
    case none
    case save(BrowserCredentialSaveCandidate)
    case strongPassword(BrowserCredentialFillRequest)
    case suggestions(BrowserCredentialFillRequest)

    static func resolve(
        saveCandidate: BrowserCredentialSaveCandidate?,
        fillRequest: BrowserCredentialFillRequest?
    ) -> BrowserCredentialChromePresentation {
        if let saveCandidate {
            return .save(saveCandidate)
        }
        guard let fillRequest else { return .none }
        switch fillRequest.passwordKind {
        case .current:
            return .suggestions(fillRequest)
        case .new:
            return .strongPassword(fillRequest)
        }
    }
}
