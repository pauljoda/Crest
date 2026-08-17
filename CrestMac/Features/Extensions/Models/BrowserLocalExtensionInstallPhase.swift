enum BrowserLocalExtensionInstallPhase {
    case unavailable
    case preparing
    case review(
        candidate: BrowserLocalExtensionCandidate,
        errorDescription: String?
    )
    case installed(
        name: String,
        compatibilityIssues: [String]
    )
    case failed(errorDescription: String)

    var candidate: BrowserLocalExtensionCandidate? {
        if case .review(let candidate, _) = self {
            return candidate
        }
        return nil
    }
}
