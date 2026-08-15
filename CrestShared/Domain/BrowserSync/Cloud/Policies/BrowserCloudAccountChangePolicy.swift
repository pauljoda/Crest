enum BrowserCloudAccountChangePolicy {
    static func requiresReconciliation(
        for transition: BrowserCloudAccountTransition,
        alreadyRequiresReconciliation: Bool
    ) -> Bool {
        switch transition {
        case .signIn:
            alreadyRequiresReconciliation
        case .signOut, .switchAccounts, .unknown:
            true
        }
    }
}
