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

    /// The preferences domain a named isolated profile persists into.
    ///
    /// Every owner of that profile's state — the browser session, the
    /// credential vault prefix, the extension registry — is addressed through
    /// this one name, so a relaunch with the same
    /// `CREST_ISOLATED_PERSISTENCE_ID` finds all of it again and none of it
    /// lands in the installed app's own domain.
    static func isolatedDefaultsSuiteName(isolationID: String) -> String {
        "\(ProductIdentity.serviceNamespace).isolated.\(isolationID)"
    }
}
