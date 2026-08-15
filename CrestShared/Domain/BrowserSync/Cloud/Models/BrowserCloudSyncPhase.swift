enum BrowserCloudSyncPhase: Equatable, Sendable {
    case disabled
    case checking
    case ready
    case syncing
    case needsReconciliation
    case waitingForAccount
    case failed(String)

    /// Whether trying the same thing again could reach a different answer.
    ///
    /// A missing account and a failed launch both heal on their own once iCloud
    /// is reachable. Everything else is either working, in progress, or waiting
    /// on a decision only somebody using Crest can make.
    var isRetryable: Bool {
        switch self {
        case .waitingForAccount, .failed:
            true
        case .disabled, .checking, .ready, .syncing, .needsReconciliation:
            false
        }
    }
}
