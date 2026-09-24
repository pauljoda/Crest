enum BrowserSystemPasswordWriteThroughError: Error, Equatable {
    case unavailable
    case invalidScope
    case missingPresentationAnchor
}
