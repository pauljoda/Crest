enum BrowserOnboardingWelcomePolicy {
    static func action(
        progressIsChecking: Bool,
        cloudPhase: BrowserCloudSyncPhase,
        hasCompletedSetup: Bool
    ) -> BrowserOnboardingWelcomeAction {
        guard !progressIsChecking, cloudPhase != .checking else {
            return .checking
        }
        return hasCompletedSetup ? .open : .setup
    }
}
