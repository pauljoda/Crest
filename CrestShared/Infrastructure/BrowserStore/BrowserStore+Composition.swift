import Foundation

extension BrowserStore {
    static func production(
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> BrowserStore {
        // Keep the persistence boundary safe even if a future composition root
        // accidentally calls `production` for a fixture or preview launch.
        // Sample Spaces must never replace the installed session or be staged as
        // Cloud tombstones for the user's real Space IDs.
        if BrowserLaunchIsolationPolicy.requiresIsolation(launchEnvironment) {
            return isolatedLaunch(launchEnvironment: launchEnvironment)
        }
        return production(
            persistence: UserDefaultsBrowserSessionPersistence(),
            syncPersistence: UserDefaultsBrowserSyncJournalPersistence(),
            credentialVault: KeychainCredentialVault()
        )
    }

    static func production(
        persistence: any BrowserSessionPersisting,
        syncPersistence: any BrowserSyncJournalPersisting,
        credentialVault: any CredentialVault
    ) -> BrowserStore {
        var session = persistence.load() ?? .freshInstallSeed
        session.repairRuntimeIntegrity()
        session.cleanupCurrentTabsUsingSpacePreferences()
        session.applyDataRetentionPolicies()
        session.selectDefaultSpaceForLaunch()
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: syncPersistence
        )
        persistence.save(session)
        let store = BrowserStore(
            session: session,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator
        )
        store.beginInitialSyncStaging(session: session)
        return store
    }

    static func preview() -> BrowserStore {
        BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
    }

    static func isolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserStore {
        if let isolationID = launchEnvironment.persistentIsolationID {
            if let store = persistentIsolatedLaunch(
                launchEnvironment: launchEnvironment,
                isolationID: isolationID
            ) {
                return store
            }
        }
        return inMemoryIsolatedLaunch(launchEnvironment: launchEnvironment)
    }

    private static func inMemoryIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserStore {
        var session = isolatedFixtureSession(for: launchEnvironment)
        session.repairRuntimeIntegrity()
        session.cleanupCurrentTabsUsingSpacePreferences()
        session.applyDataRetentionPolicies()
        session.selectDefaultSpaceForLaunch()
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence()
        )
        let store = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            syncCoordinator: syncCoordinator
        )
        store.beginInitialSyncStaging(session: session)
        return store
    }

    private static func persistentIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment,
        isolationID: String
    ) -> BrowserStore? {
        let namespace = BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(
            isolationID: isolationID
        )
        guard let defaults = UserDefaults(suiteName: namespace) else { return nil }
        let persistence = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: InMemoryBrowserFaviconStore()
        )
        var session =
            persistence.load()
            ?? isolatedFixtureSession(for: launchEnvironment)
        session.repairRuntimeIntegrity()
        session.cleanupCurrentTabsUsingSpacePreferences()
        session.applyDataRetentionPolicies()
        session.selectDefaultSpaceForLaunch()
        persistence.save(session)
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence()
        )
        let store = BrowserStore(
            session: session,
            persistence: persistence,
            credentialVault: KeychainCredentialVault(servicePrefix: namespace),
            syncCoordinator: syncCoordinator
        )
        store.beginInitialSyncStaging(session: session)
        return store
    }

    private static func isolatedFixtureSession(
        for launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserSession {
        #if CREST_PERFORMANCE_HARNESS
            if let performanceSession = BrowserPerformanceSoakFixture.makeSession(
                baseURLString: launchEnvironment.performanceBaseURLString,
                rawTabCount: launchEnvironment.performanceTabCount,
                isHeavy: launchEnvironment.performanceHeavySession,
                runID: launchEnvironment.performanceRunID
            ) {
                return performanceSession
            }
        #endif
        return launchEnvironment.presentsShowcaseSession ? .showcase : .preview
    }

    static func privateBrowsing() -> BrowserStore {
        BrowserStore(
            session: .privateBrowsing(),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: PrivateBrowsingCredentialVault(),
            browsingMode: .privateBrowsing
        )
    }
}
