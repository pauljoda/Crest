extension BrowserCloudSyncPhase {
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
