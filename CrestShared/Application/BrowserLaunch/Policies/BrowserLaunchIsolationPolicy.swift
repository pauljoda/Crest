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

    /// Keeps page and extension WebKit storage in the same privacy class.
    /// WebKit treats a nonpersistent page store as private data and denies a
    /// persistent extension context access unless private-data access is
    /// granted. Named isolated profiles intentionally persist both sides.
    static func usesEphemeralProfileStorage(
        _ environment: BrowserLaunchEnvironment
    ) -> Bool {
        requiresIsolation(environment)
            && environment.persistentIsolationID == nil
    }
}
