enum BrowserMozillaAddonsInstallPhase {
    case unavailable
    case preparing
    case installed(String)
    case review(BrowserMozillaAddonsCandidate, errorDescription: String?)
    case failed(String)

    static func resolve(
        isPreparing: Bool,
        installedName: String?,
        candidate: BrowserMozillaAddonsCandidate?,
        errorDescription: String?
    ) -> BrowserMozillaAddonsInstallPhase {
        switch (isPreparing, installedName, candidate, errorDescription) {
        case (true, _, _, _):
            return .preparing
        case (false, .some(let installedName), _, _):
            return .installed(installedName)
        case (false, nil, .some(let candidate), let errorDescription):
            return .review(candidate, errorDescription: errorDescription)
        case (false, nil, nil, .some(let errorDescription)):
            return .failed(errorDescription)
        case (false, nil, nil, nil):
            return .unavailable
        }
    }

    var candidate: BrowserMozillaAddonsCandidate? {
        guard case .review(let candidate, _) = self else { return nil }
        return candidate
    }

    var headerTitle: String {
        switch self {
        case .installed(let name):
            return name
        case .review(let candidate, _):
            return "Add \(candidate.displayName)?"
        case .unavailable, .preparing, .failed:
            return "Add Extension to Crest"
        }
    }
}
