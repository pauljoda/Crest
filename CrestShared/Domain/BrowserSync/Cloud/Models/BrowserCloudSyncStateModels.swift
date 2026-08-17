/// The related account, phase, and availability states surfaced by cloud sync.
enum BrowserCloudAccountState: Equatable, Sendable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var description: String {
        switch self {
        case .checking: "Checking"
        case .available: "Available"
        case .noAccount: "Not signed in"
        case .restricted: "Restricted"
        case .temporarilyUnavailable: "Temporarily unavailable"
        case .couldNotDetermine: "Could not determine"
        }
    }
}

enum BrowserCloudAccountTransition: Equatable, Sendable {
    case signIn
    case signOut
    case switchAccounts
    case unknown
}

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

    var description: String {
        switch self {
        case .disabled: "Off"
        case .checking: "Checking iCloud"
        case .ready: "Up to date"
        case .syncing: "Syncing"
        case .needsReconciliation: "Choose which copy to keep"
        case .waitingForAccount: "Waiting for iCloud"
        case .failed: "Needs attention"
        }
    }
}
