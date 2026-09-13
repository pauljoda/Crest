enum BrowserOnboardingWelcomePolicy {
    static func action(
        progressIsChecking: Bool,
        cloudPhase: BrowserCloudSyncPhase,
        hasCompletedSetup: Bool,
        entryPoint: BrowserOnboardingEntryPoint = .firstRun
    ) -> BrowserOnboardingWelcomeAction {
        guard !progressIsChecking, cloudPhase != .checking else {
            return .checking
        }
        return hasCompletedSetup && entryPoint != .rerun ? .open : .setup
    }
}
