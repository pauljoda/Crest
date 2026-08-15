enum MobileBrowserAutomaticOnboardingPolicy {
    static func shouldPresent(
        forceOnboarding: Bool,
        usesIsolatedLaunch: Bool
    ) -> Bool {
        forceOnboarding || !usesIsolatedLaunch
    }

    static func showsLaunchGate(
        automaticallyPresentsOnboarding: Bool,
        isLaunchGateActive: Bool
    ) -> Bool {
        automaticallyPresentsOnboarding && isLaunchGateActive
    }
}
