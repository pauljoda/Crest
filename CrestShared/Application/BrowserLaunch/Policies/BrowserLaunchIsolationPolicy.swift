enum BrowserLaunchIsolationPolicy {
    static func presentsInstalledApplicationUI(
        _ environment: BrowserLaunchEnvironment
    ) -> Bool {
        !environment.isXCTestRuntime
    }

    static func requiresIsolation(
        _ environment: BrowserLaunchEnvironment
    ) -> Bool {
        environment.isXCTestRuntime
            || environment.isSwiftUIPreviewRuntime
            || environment.explicitlyRequiresIsolation
            || environment.resetsSession
            || environment.presentsShowcaseSession
            || environment.usesInMemoryCredentialVault
            || environment.forcesOnboardingWelcome
            || environment.forcesMacOnboardingSetup
            || environment.forcesMobileOnboardingSetup
            || environment.performanceBaseURLString != nil
            || environment.isolatedSoftwareUpdateFeedURL != nil
    }
}
